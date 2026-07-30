{
  lib,
  network,
  pkgs,
  ...
}: let
  storage = import ./spdk-storage-constants.nix;
  inherit
    (storage)
    iobufSmallPoolCount
    incompleteLvol
    incompleteMount
    modelsLvol
    modelsMount
    modelsNqn
    modelsSerial
    modelsSnapshot
    modelsSnapshotPattern
    rpcSocket
    ;

  # The one snapshot this host publishes; clients name the same UUID.
  pinnedSnapshotAlias = "${storage.lvstore}/${modelsSnapshot.name}";

  rdma = network.hosts."trex-rdma";
  rdmaAddress = network.ipOf "fabric" rdma.addresses.fabric;
  rdmaInterface = "mlxlan0v1";
  rdmaVerbsDevice = "mlx5_1";

  modelsMountUnit = "mnt-optane-models.mount";
  incompleteMountUnit = "var-lib-qbittorrent-incomplete.mount";

  assembleScript = pkgs.writeShellApplication {
    name = "spdk-storage-assemble";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.kmod
      pkgs.spdk-ublk
    ];
    text = ''
      rpc() {
        timeout 15s spdk-rpc -s ${rpcSocket} "$@"
      }

      echo "spdk-storage: waiting at most 30 seconds for ${rpcSocket}"
      rpc_ready=false
      for _ in $(seq 1 30); do
        if rpc rpc_get_methods --current >/dev/null 2>&1; then
          rpc_ready=true
          break
        fi
        sleep 1
      done
      "$rpc_ready" || {
        echo "spdk-storage: RPC socket did not become usable; storage remains absent" >&2
        exit 1
      }

      # --wait-for-rpc exposes framework_start_init only before framework
      # initialisation. UUID generation is a pre-init-only option and must be
      # set before a single namespace is attached, or the RAID superblock's
      # member UUIDs cannot match on the next boot.
      methods=$(rpc rpc_get_methods --current)
      if jq -e 'index("framework_start_init") != null' <<<"$methods" >/dev/null; then
        echo "spdk-storage: sizing the iobuf small pool before framework init"
        rpc iobuf_set_options --small-pool-count ${toString iobufSmallPoolCount} >/dev/null
        echo "spdk-storage: enabling deterministic NVMe UUID generation before framework init"
        rpc bdev_nvme_set_options --generate-uuids >/dev/null
        rpc framework_start_init >/dev/null
      else
        echo "spdk-storage: framework is already initialised; preserving its current state"
      fi
      timeout 60s spdk-rpc -s ${rpcSocket} framework_wait_init >/dev/null

      mapfile -t optane_bdfs < <(
        for device in /sys/bus/pci/devices/*; do
          [ -r "$device/vendor" ] || continue
          [ "$(cat "$device/vendor")" = 0x8086 ] || continue
          [ "$(cat "$device/device")" = 0x2700 ] || continue
          [ "$(basename "$(readlink -f "$device/driver")")" = vfio-pci ] || continue
          basename "$device"
        done | sort
      )
      if [ "''${#optane_bdfs[@]}" -ne 8 ]; then
        echo "spdk-storage: found ''${#optane_bdfs[@]} vfio-bound Optane 905Ps, expected 8; storage remains absent" >&2
        exit 1
      fi

      controllers=$(rpc bdev_nvme_get_controllers)
      for index in "''${!optane_bdfs[@]}"; do
        bdf="''${optane_bdfs[$index]}"
        if jq -e --arg address "$bdf" \
          'any(.[]; any(.ctrlrs[]?; .trid.traddr == $address))' \
          <<<"$controllers" >/dev/null; then
          echo "spdk-storage: $bdf is already attached"
          continue
        fi
        echo "spdk-storage: attaching $bdf as opt$index"
        rpc bdev_nvme_attach_controller -b "opt$index" -t pcie -a "$bdf" >/dev/null
        controllers=$(rpc bdev_nvme_get_controllers)
      done

      echo "spdk-storage: waiting at most 60 seconds for optraid and optstore"
      array_ready=false
      for _ in $(seq 1 60); do
        raids=$(rpc bdev_raid_get_bdevs all)
        lvols=$(rpc bdev_lvol_get_lvols)
        if jq -e '
            any(.[];
              .name == "optraid"
              and .state == "online"
              and .raid_level == "raid0"
              and .strip_size_kb == 64
              and .superblock == true
              and .num_base_bdevs == 8
              and .num_base_bdevs_discovered == 8
              and .num_base_bdevs_operational == 8)
          ' <<<"$raids" >/dev/null \
          && jq -e --arg models ${lib.escapeShellArg modelsLvol} \
            --arg incomplete ${lib.escapeShellArg incompleteLvol} '
              any(.[]; .alias == $models and .is_snapshot == false)
              and any(.[]; .alias == $incomplete and .is_snapshot == false)
            ' <<<"$lvols" >/dev/null; then
          array_ready=true
          break
        fi
        sleep 1
      done
      "$array_ready" || {
        echo "spdk-storage: optraid/optstore did not assemble completely; refusing to expose partial storage" >&2
        exit 1
      }

      modprobe ublk_drv
      if ! disks=$(rpc ublk_get_disks 2>/dev/null); then
        echo "spdk-storage: creating the ublk target"
        rpc ublk_create_target >/dev/null
        disks=$(rpc ublk_get_disks)
      elif jq -e 'length == 0' <<<"$disks" >/dev/null; then
        # SPDK 26.01 reports [] both for an existing empty target and for no
        # target at all. Creation resolves the ambiguity; EEXIST is harmless.
        if rpc ublk_create_target >/dev/null 2>&1; then
          echo "spdk-storage: created the missing ublk target"
        else
          echo "spdk-storage: ublk target already exists with no disks"
        fi
        disks=$(rpc ublk_get_disks)
      fi

      ensure_ublk() {
        local lvol=$1
        local id=$2
        local queues=$3
        local path="/dev/ublkb$id"
        local uuid
        local disk_uuid

        uuid=$(rpc bdev_get_bdevs -b "$lvol" | jq -er '.[0].uuid')
        disk_uuid=$(jq -r --argjson id "$id" \
          '.[] | select(.id == $id) | .bdev_name' <<<"$disks")

        if [ -b "$path" ]; then
          if [ "$disk_uuid" = "$uuid" ]; then
            echo "spdk-storage: $path already exposes $lvol"
            return
          fi
          if [ -z "$disk_uuid" ]; then
            echo "spdk-storage: recovering surviving $path as $lvol"
            rpc ublk_recover_disk "$lvol" "$id" >/dev/null
            disks=$(rpc ublk_get_disks)
            disk_uuid=$(jq -r --argjson id "$id" \
              '.[] | select(.id == $id) | .bdev_name' <<<"$disks")
            [ "$disk_uuid" = "$uuid" ] || {
              echo "spdk-storage: recovery of $path did not bind $lvol" >&2
              exit 1
            }
            return
          fi
          echo "spdk-storage: $path is an active block device for unexpected bdev $disk_uuid; refusing to replace it" >&2
          exit 1
        fi

        # A consumer opening a missing /dev/ublkbN for output creates a regular
        # file. Never let mount(8), fsck, or another writer touch such a file.
        if [ -e "$path" ]; then
          echo "spdk-storage: removing stale non-block path $path" >&2
          rm -f -- "$path"
        fi

        if [ -n "$disk_uuid" ]; then
          echo "spdk-storage: SPDK has stale state for missing $path; stopping it before recreation"
          rpc ublk_stop_disk "$id" >/dev/null
          disks=$(rpc ublk_get_disks)
        fi

        echo "spdk-storage: starting $path from $lvol ($queues queues, depth 128)"
        rpc ublk_start_disk "$lvol" "$id" -q "$queues" -d 128 >/dev/null
        for _ in $(seq 1 10); do
          [ -b "$path" ] && break
          sleep 1
        done
        [ -b "$path" ] || {
          echo "spdk-storage: $path is not a block device after ublk_start_disk" >&2
          [ ! -e "$path" ] || rm -f -- "$path"
          exit 1
        }
        disks=$(rpc ublk_get_disks)
      }

      ensure_ublk ${lib.escapeShellArg modelsLvol} 0 4
      ensure_ublk ${lib.escapeShellArg incompleteLvol} 1 4
      [ -b /dev/ublkb0 ] && [ -b /dev/ublkb1 ]
      echo "spdk-storage: optraid is online 8/8 and both ublk devices are real block devices"
    '';
  };

  exportScript = pkgs.writeShellApplication {
    name = "spdk-models-export";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.iproute2
      pkgs.jq
      pkgs.spdk-ublk
    ];
    text = ''
      rpc() {
        timeout 15s spdk-rpc -s ${rpcSocket} "$@"
      }

      # RDMA transports enumerate verbs devices exactly once. Do not create
      # the transport until the dedicated VF has both its address and mlx5_1.
      echo "spdk-export: waiting at most 30 seconds for ${rdmaInterface}, ${rdmaAddress}, and ${rdmaVerbsDevice}"
      fabric_ready=false
      for _ in $(seq 1 30); do
        if ip -4 -o address show dev ${rdmaInterface} |
          awk '{print $4}' | grep -qx '${rdmaAddress}/24' \
          && [ -e /sys/class/infiniband/${rdmaVerbsDevice}/device/net/${rdmaInterface} ]; then
          fabric_ready=true
          break
        fi
        sleep 1
      done
      "$fabric_ready" || {
        echo "spdk-export: RDMA VF is not ready; transport was deliberately not created" >&2
        exit 1
      }

      transports=$(rpc nvmf_get_transports)
      if jq -e 'any(.[]; .trtype == "RDMA")' <<<"$transports" >/dev/null; then
        echo "spdk-export: RDMA transport already exists"
      else
        echo "spdk-export: creating RDMA transport after the VF is ready"
        rpc nvmf_create_transport -t RDMA >/dev/null
      fi

      subsystems=$(rpc nvmf_get_subsystems)
      if ! jq -e --arg nqn ${lib.escapeShellArg modelsNqn} \
        'any(.[]; .nqn == $nqn)' <<<"$subsystems" >/dev/null; then
        rpc nvmf_create_subsystem ${lib.escapeShellArg modelsNqn} \
          -s ${lib.escapeShellArg modelsSerial} -a >/dev/null
        subsystems=$(rpc nvmf_get_subsystems)
      fi

      if ! jq -e --arg nqn ${lib.escapeShellArg modelsNqn} \
        --arg address ${lib.escapeShellArg rdmaAddress} '
          any(.[]; .nqn == $nqn and
            any(.listen_addresses[]?;
              .trtype == "RDMA"
              and .adrfam == "IPv4"
              and .traddr == $address
              and .trsvcid == "4420"))
        ' <<<"$subsystems" >/dev/null; then
        rpc nvmf_subsystem_add_listener ${lib.escapeShellArg modelsNqn} \
          -t rdma -f ipv4 -a ${lib.escapeShellArg rdmaAddress} -s 4420 >/dev/null
      fi

      # Export the PINNED snapshot from spdk-storage-constants.nix, not simply
      # the newest one. Clients mount /dev/disk/by-id/nvme-uuid.<uuid>, so what
      # is exported must be exactly what their configuration names; picking
      # "newest" would silently move every client onto a snapshot its own
      # config never mentioned, and would defeat rollback.
      lvols=$(rpc bdev_lvol_get_lvols)
      snapshot=$(jq -r --arg alias ${lib.escapeShellArg pinnedSnapshotAlias} '
          [.[] | select(.is_snapshot == true and .alias == $alias)]
          | last | .alias // empty
        ' <<<"$lvols")
      if [ -z "$snapshot" ]; then
        echo "spdk-export: pinned snapshot ${pinnedSnapshotAlias} does not exist." >&2
        echo "spdk-export: run spdk-models-snapshot and update modelsSnapshot in" >&2
        echo "spdk-export: spdk-storage-constants.nix, or restore that snapshot." >&2
        available=$(jq -r --arg pattern ${lib.escapeShellArg modelsSnapshotPattern} '
            [.[] | select(.is_snapshot == true and (.alias | test($pattern))) | .alias]
            | sort | join(" ")
          ' <<<"$lvols")
        echo "spdk-export: snapshots present: ''${available:-none}" >&2
      fi

      subsystems=$(rpc nvmf_get_subsystems)
      mapfile -t current_nsids < <(jq -r --arg nqn ${lib.escapeShellArg modelsNqn} '
          .[] | select(.nqn == $nqn) | .namespaces[]?.nsid
        ' <<<"$subsystems")

      if [ -z "$snapshot" ]; then
        for nsid in "''${current_nsids[@]}"; do
          rpc nvmf_subsystem_remove_ns ${lib.escapeShellArg modelsNqn} "$nsid" >/dev/null
        done
        echo "spdk-export: WARNING: no existing models snapshot found; ${modelsNqn} has zero namespaces" >&2
        exit 0
      fi

      snapshot_bdev=$(rpc bdev_get_bdevs -b "$snapshot")
      if ! jq -e '.[0].supported_io_types.write == false' \
        <<<"$snapshot_bdev" >/dev/null; then
        for nsid in "''${current_nsids[@]}"; do
          rpc nvmf_subsystem_remove_ns ${lib.escapeShellArg modelsNqn} "$nsid" >/dev/null
        done
        echo "spdk-export: refusing writable bdev $snapshot; subsystem was left with zero namespaces" >&2
        exit 1
      fi
      snapshot_uuid=$(jq -er '.[0].uuid' <<<"$snapshot_bdev")

      # The two halves of the pin must describe the same object. If they drift,
      # trex would export the named snapshot while clients look for a UUID that
      # is not there, and the failure would appear on the clients rather than
      # here. Refuse instead, and say exactly what to correct.
      if [ "$snapshot_uuid" != ${lib.escapeShellArg modelsSnapshot.uuid} ]; then
        for nsid in "''${current_nsids[@]}"; do
          rpc nvmf_subsystem_remove_ns ${lib.escapeShellArg modelsNqn} "$nsid" >/dev/null
        done
        echo "spdk-export: pin mismatch in spdk-storage-constants.nix." >&2
        echo "spdk-export:   modelsSnapshot.name = ${modelsSnapshot.name}" >&2
        echo "spdk-export:   modelsSnapshot.uuid = ${modelsSnapshot.uuid}" >&2
        echo "spdk-export:   that snapshot's real uuid = $snapshot_uuid" >&2
        exit 1
      fi

      selected_present=$(jq -r --arg nqn ${lib.escapeShellArg modelsNqn} \
        --arg uuid "$snapshot_uuid" '
          any(.[]; .nqn == $nqn and
            any(.namespaces[]?; .bdev_name == $uuid))
        ' <<<"$subsystems")
      if [ "$selected_present" != true ]; then
        rpc nvmf_subsystem_add_ns ${lib.escapeShellArg modelsNqn} "$snapshot" >/dev/null
      fi

      # Add first, remove second: clients never see an empty subsystem during
      # an ordinary boot-time move from an older snapshot to the newest one.
      subsystems=$(rpc nvmf_get_subsystems)
      mapfile -t stale_nsids < <(jq -r --arg nqn ${lib.escapeShellArg modelsNqn} \
        --arg uuid "$snapshot_uuid" '
          .[] | select(.nqn == $nqn) | .namespaces[]?
          | select(.bdev_name != $uuid) | .nsid
        ' <<<"$subsystems")
      for nsid in "''${stale_nsids[@]}"; do
        rpc nvmf_subsystem_remove_ns ${lib.escapeShellArg modelsNqn} "$nsid" >/dev/null
      done

      echo "spdk-export: LISTEN ${rdmaAddress}:4420; exporting read-only snapshot $snapshot"
    '';
  };
in {
  boot.kernelModules = ["ublk_drv"];

  # noauto removes these units from local-fs.target's boot transaction.
  # nofail and the bounded device wait remain as defence in depth for manual
  # starts and RequiresMountsFor consumers.
  fileSystems.${modelsMount} = {
    device = "/dev/ublkb0";
    fsType = "xfs";
    options = [
      "noatime"
      "nofail"
      "noauto"
      "x-systemd.device-timeout=10s"
    ];
  };
  fileSystems.${incompleteMount} = {
    device = "/dev/ublkb1";
    fsType = "xfs";
    options = [
      "noatime"
      "nofail"
      "noauto"
      "x-systemd.device-timeout=10s"
    ];
  };

  environment.systemPackages = [
    assembleScript
    exportScript
  ];

  systemd.services.spdk-storage-assemble = {
    description = "Assemble SPDK Optane RAID, lvstore, and ublk disks";
    after = ["spdk-tgt.service"];
    requires = ["spdk-tgt.service"];
    unitConfig = {
      OnSuccess = [
        modelsMountUnit
        incompleteMountUnit
      ];
      StartLimitIntervalSec = 0;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "150s";
      ExecStart = "${assembleScript}/bin/spdk-storage-assemble";
    };
  };

  # A timer activates the storage transaction asynchronously. It is not part
  # of multi-user.target's ordering graph, so absent hardware cannot delay SSH
  # or completion of the normal boot.
  systemd.timers.spdk-storage-assemble = {
    description = "Retry non-fatal SPDK Optane assembly";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2s";
      OnUnitInactiveSec = "1min";
      AccuracySec = "1s";
      Unit = "spdk-storage-assemble.service";
    };
  };

  # OnSuccess mounts promptly. These timers additionally recover a mount whose
  # earlier job failed while the array was absent; neither timer is ordered
  # before a boot target.
  systemd.timers.spdk-models-mount = {
    description = "Retry the non-fatal SPDK models mount";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "10s";
      OnUnitInactiveSec = "1min";
      AccuracySec = "1s";
      Unit = modelsMountUnit;
    };
  };
  systemd.timers.spdk-incomplete-mount = {
    description = "Retry the non-fatal SPDK qBittorrent incomplete mount";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "10s";
      OnUnitInactiveSec = "1min";
      AccuracySec = "1s";
      Unit = incompleteMountUnit;
    };
  };

  systemd.services.spdk-models-export = {
    description = "Export the pinned models snapshot over NVMe/RDMA";
    after = [
      "spdk-storage-assemble.service"
      "systemd-networkd.service"
      "sys-subsystem-net-devices-${rdmaInterface}.device"
    ];
    requires = ["spdk-storage-assemble.service"];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "60s";
      ExecStart = "${exportScript}/bin/spdk-models-export";
    };
  };

  systemd.timers.spdk-models-export = {
    description = "Retry non-fatal snapshot-only SPDK NVMe/RDMA export";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5s";
      OnUnitInactiveSec = "1min";
      AccuracySec = "1s";
      Unit = "spdk-models-export.service";
    };
  };

  # These consumers retain RequiresMountsFor, but they are timer-started rather
  # than members of a boot target. Missing Optane storage makes the service
  # fail and retry without ever making multi-user.target wait.
  systemd.services.qbittorrent.wantedBy = lib.mkForce [];
  systemd.timers.qbittorrent-storage = {
    description = "Start qBittorrent when its Optane incomplete mount is available";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "15s";
      OnUnitInactiveSec = "1min";
      AccuracySec = "1s";
      Unit = "qbittorrent.service";
    };
  };

  systemd.services."container@arr-servers".wantedBy = lib.mkForce [];
  systemd.timers.arr-servers-storage = {
    description = "Start arr-servers when its Optane incomplete mount is available";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "20s";
      OnUnitInactiveSec = "1min";
      AccuracySec = "1s";
      Unit = "container@arr-servers.service";
    };
  };
}
