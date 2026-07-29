{pkgs, ...}: let
  rpcSocket = "/run/spdk/spdk.sock";
  modelsMount = "/mnt/optane/models";
  lvstore = "optstore";
  modelsLvol = "${lvstore}/models";
  nqn = "nqn.2026-07.link.satanic.trex:models";

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
      keep=''${SPDK_SNAPSHOT_KEEP:-2}
      rpc() { spdk-rpc -s ${rpcSocket} "$@"; }

      mountpoint -q ${modelsMount} || {
        echo "${modelsMount} is not mounted; nothing to snapshot" >&2
        exit 1
      }
      rpc nvmf_get_subsystems | jq -e --arg n ${nqn} '.[] | select(.nqn == $n)' >/dev/null || {
        echo "subsystem ${nqn} does not exist yet" >&2
        exit 1
      }

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

      # Swap the export over: add the new namespace, then drop the previous
      # ones so a client never sees an empty subsystem.
      old_nsids=$(rpc nvmf_get_subsystems |
        jq -r --arg n ${nqn} '.[] | select(.nqn == $n) | .namespaces[].nsid')
      rpc nvmf_subsystem_add_ns ${nqn} "${lvstore}/$snap" >/dev/null
      for nsid in $old_nsids; do
        rpc nvmf_subsystem_remove_ns ${nqn} "$nsid" >/dev/null
      done
      echo "exported ${lvstore}/$snap over ${nqn}"

      # Retire the oldest snapshots. A snapshot backing a clone, or one a
      # client still holds, refuses deletion — that is fine, skip it.
      mapfile -t stale < <(rpc bdev_lvol_get_lvols |
        jq -r '.[] | select(.is_snapshot) | .alias' |
        grep -E '/models-[0-9]{8}-[0-9]{6}$' | sort | head -n -"$keep")
      for lv in "''${stale[@]:-}"; do
        [ -n "$lv" ] || continue
        if rpc bdev_lvol_delete "$lv" >/dev/null 2>&1; then
          echo "deleted old snapshot $lv"
        else
          echo "kept $lv (still in use)"
        fi
      done
    '';
  };
in {
  environment.systemPackages = [snapshotScript];

  # Manual for now: run after adding models. The NVMe-oF export itself is still
  # brought up by hand after boot (phase-2 automation pending), so there is no
  # timer here yet — a scheduled snapshot against a missing subsystem would
  # only produce noise.
  systemd.services.spdk-models-snapshot = {
    description = "Publish a frozen-consistent snapshot of the models volume over NVMe-oF";
    after = ["spdk-tgt.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${snapshotScript}/bin/spdk-models-snapshot";
    };
  };
}
