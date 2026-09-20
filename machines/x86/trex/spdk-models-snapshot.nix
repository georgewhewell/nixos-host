{pkgs, ...}: let
  storage = import ./spdk-storage-constants.nix;
  inherit
    (storage)
    lvstore
    modelsLvol
    modelsMount
    modelsNqn
    rpcSocket
    ;

  # Shared model data must be traversable by the clients' Nix build users.
  modelPermissions = pkgs.writeTextDir "lib/tmpfiles.d/flm-models.conf" ''
    z ${modelsMount}/flm 0755 - - -
  '';

  # Publishing the live, read-write-mounted models volume over NVMe-oF is
  # unsafe: XFS is not a shared-disk filesystem, so a client mounting it — even
  # with -o ro — caches metadata that this host mutates underneath it, and a
  # live XFS log can only be mounted read-only with norecovery, i.e. knowingly
  # inconsistent. Instead we publish an SPDK lvol snapshot, which the lvol
  # layer reports as write=false, taken while the filesystem is frozen so the
  # log is clean and clients need no recovery at all.
  snapshotScript = pkgs.writeShellApplication {
    name = "spdk-models-snapshot";
    runtimeInputs = [pkgs.spdk-ublk pkgs.util-linux pkgs.jq pkgs.coreutils];
    text = ''
      set -euo pipefail
      rpc() { spdk-rpc -s ${rpcSocket} "$@"; }

      mountpoint -q ${modelsMount} || {
        echo "${modelsMount} is not mounted; nothing to snapshot" >&2
        exit 1
      }
      rpc nvmf_get_subsystems | jq -e --arg n ${modelsNqn} '.[] | select(.nqn == $n)' >/dev/null || {
        echo "subsystem ${modelsNqn} does not exist yet" >&2
        exit 1
      }

      # The models mount arrives after boot-time tmpfiles on this host.
      ${pkgs.systemd}/bin/systemd-tmpfiles --create ${modelPermissions}/lib/tmpfiles.d/flm-models.conf

      # Refuse to freeze a filesystem whose store cannot absorb writes.
      #
      # 2026-07-30 incident: optstore reached free_clusters=0 while ~1.2 TiB was
      # still being copied in. `models` is thin, so every write needed a fresh
      # cluster, got ENOSPC, and XFS silently lost writeback on 26 files. Then
      # fsfreeze here forced a log write, which also failed, and XFS shut the
      # filesystem down. Sizes read from `find` still looked correct throughout,
      # because the correct sizes were in log records that never reached disk.
      #
      # A freeze is the worst possible moment to discover the store is full, so
      # check first and say so loudly.
      free=$(rpc bdev_lvol_get_lvstores |
        jq -er --arg n ${lvstore} '.[] | select(.name == $n) | .free_clusters')
      cluster=$(rpc bdev_lvol_get_lvstores |
        jq -er --arg n ${lvstore} '.[] | select(.name == $n) | .cluster_size')
      free_gib=$(( free * cluster / 1073741824 ))
      min_gib=''${SPDK_SNAPSHOT_MIN_FREE_GIB:-64}
      echo "${lvstore}: $free_gib GiB free ($free clusters)"
      if [ "$free_gib" -lt "$min_gib" ]; then
        echo "refusing to snapshot: only $free_gib GiB free, want >= $min_gib GiB" >&2
        echo "freezing a filesystem on a full lvstore shuts it down; free space first" >&2
        echo "(override with SPDK_SNAPSHOT_MIN_FREE_GIB if you know better)" >&2
        exit 1
      fi

      snap="models-$(date +%Y%m%d-%H%M%S)"

      # Always thaw, even if the snapshot RPC fails: a filesystem left frozen
      # blocks every writer on it indefinitely.
      thaw() { fsfreeze -u ${modelsMount} 2>/dev/null || true; }
      trap thaw EXIT
      fsfreeze -f ${modelsMount}
      rpc bdev_lvol_snapshot ${modelsLvol} "$snap" >/dev/null
      thaw
      trap - EXIT
      echo "created snapshot ${lvstore}/$snap"

      # Read the immutable snapshot's UUID for the pin below.
      snapshot_bdev=$(rpc bdev_get_bdevs -b "${lvstore}/$snap")
      jq -e '.[0].supported_io_types.write == false' <<<"$snapshot_bdev" >/dev/null || {
        echo "new snapshot ${lvstore}/$snap unexpectedly supports writes; refusing to offer it" >&2
        exit 1
      }
      snap_uuid=$(jq -er '.[0].uuid' <<<"$snapshot_bdev")

      # Deliberately does NOT touch the export. Which snapshot is served is
      # decided by modelsSnapshot in spdk-storage-constants.nix, and clients
      # mount that UUID by name. Swapping the namespace here would yank the
      # block device out from under every connected client and move them onto a
      # snapshot their own configuration never mentions.
      cat <<EOF

Created ${lvstore}/$snap

To publish it, set this in machines/x86/trex/spdk-storage-constants.nix:

  modelsSnapshot = {
    name = "$snap";
    uuid = "$snap_uuid";
  };

then: deploy trex, and DRAIN EVERY CLIENT (unmount /models and stop
nvme-trex-models on strix-1/2/3/4; unmount /mnt/trex-models and stop the unit
on fuckup). All four Strix hosts now netboot. The export deliberately refuses
to swap namespaces while controllers are connected -- SPDK 26.01 crashes on a
live swap -- so it converges within a minute of the last client dropping. Then
reboot all four Strix hosts and restart the fuckup client. Full procedure:
spdk-storage-constants.nix.

Nothing is serving it yet; the current pin is still in effect.
EOF

      # No automatic retirement: an old snapshot may still be the pin that a
      # client -- or a rollback -- depends on. Deleting snapshots is a separate,
      # deliberate act. List what has accumulated so it is visible.
      echo "Snapshots present:"
      rpc bdev_lvol_get_lvols |
        jq -r '.[] | select(.is_snapshot) | .alias' |
        grep -E '/models-[0-9]{8}-[0-9]{6}$' | sort | sed 's/^/  /'
    '';
  };
in {
  environment.systemPackages = [snapshotScript];
  systemd.tmpfiles.packages = [modelPermissions];

  # Snapshots remain an explicit administrative action: rebooting never creates
  # one, and creating one never changes what is served. Publishing is the
  # separate act of bumping modelsSnapshot in spdk-storage-constants.nix.
  systemd.services.spdk-models-snapshot = {
    description = "Create a frozen-consistent snapshot of the models volume";
    after = [
      "spdk-storage-assemble.service"
      "spdk-models-export.service"
      "mnt-optane-models.mount"
    ];
    requires = ["spdk-storage-assemble.service"];
    unitConfig.RequiresMountsFor = modelsMount;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${snapshotScript}/bin/spdk-models-snapshot";
    };
  };
}
