{
  lib,
  network,
  pkgs,
  ...
}: let
  storage = import ./spdk-storage-constants.nix;
  inherit
    (storage)
    iobufLargePoolCount
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
  # The PF itself (2026-08-08). Was the SR-IOV VF mlxlan0v1, which existed only
  # because an OVS internal port has no verbs device and the switchdev PF had
  # none either. With the eswitch gone the PF is a normal netdev with a normal
  # verbs device, and RoCE no longer traverses a representor.
  rdmaInterface = "mlxlan0";
  # The verbs device name (mlx5_N) is handed out in mlx5 probe order, not
  # derived from any hardware-stable id, so unlike mlxlan0v1 it can shift when
  # the card is re-seated or the PCIe tree is re-walked. Derive it from the
  # VF's own sysfs node at runtime instead of pinning "mlx5_1" here — see
  # machines/x86/trex/default.nix for the same rule applied to netdev names.

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
        echo "spdk-storage: sizing the iobuf pools before framework init"
        rpc iobuf_set_options \
          --small-pool-count ${toString iobufSmallPoolCount} \
          --large-pool-count ${toString iobufLargePoolCount} >/dev/null
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
        # The attach RPC does not return until bdev examine completes, and for
        # the LAST array member that examine is the whole chain: RAID
        # superblock match plus the full blobstore load of optstore, whose
        # metadata scan grows with the store's contents. With ~1.3 TB on the
        # store that exceeds the general 15 s rpc() guard, so the unit failed
        # with 124 on every boot (attempt 1 at 22:33:02->22:33:17 on
        # 2026-07-30) and only the retry timer, finding the work already
        # finished, brought the stack up ~40 s late. Give attaches their own
        # generous budget; the first seven still return in under a second.
        timeout 120s spdk-rpc -s ${rpcSocket} \
          bdev_nvme_attach_controller -b "opt$index" -t pcie -a "$bdf" >/dev/null
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

      # Name of the verbs device backing the VF, or failure if it has not
      # registered with the RDMA stack yet.
      verbs_device_of_vf() {
        for ibdev in /sys/class/net/${rdmaInterface}/device/infiniband/*; do
          [ -e "$ibdev" ] || continue
          basename "$ibdev"
          return 0
        done
        return 1
      }

      # RDMA transports enumerate verbs devices exactly once. Do not create the
      # transport until the dedicated VF has both its address and a verbs device.
      echo "spdk-export: waiting at most 30 seconds for ${rdmaInterface}, ${rdmaAddress}, and its verbs device"
      fabric_ready=false
      verbs_device=""
      for _ in $(seq 1 30); do
        if ip -4 -o address show dev ${rdmaInterface} |
          awk '{print $4}' | grep -qx '${rdmaAddress}/24' \
          && verbs_device="$(verbs_device_of_vf)"; then
          fabric_ready=true
          break
        fi
        sleep 1
      done
      "$fabric_ready" || {
        echo "spdk-export: RDMA VF is not ready; transport was deliberately not created" >&2
        exit 1
      }
      echo "spdk-export: ${rdmaInterface} is up on verbs device $verbs_device"

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
      fi

      listener_present() {
        listener_address=$1
        listener_subsystems=$(rpc nvmf_get_subsystems) || return $?
        if jq -e --arg nqn ${lib.escapeShellArg modelsNqn} \
          --arg address "$listener_address" '
            any(.[]; .nqn == $nqn and
              any(.listen_addresses[]?;
                .trtype == "RDMA"
                and .adrfam == "IPv4"
                and .traddr == $address
                and .trsvcid == "4420"))
          ' <<<"$listener_subsystems" >/dev/null; then
          return 0
        else
          listener_rc=$?
          # jq -e uses 1 for a valid false result. Parse/RPC failures are not
          # evidence that the listener is absent and must propagate.
          [ "$listener_rc" -eq 1 ] && return 1
          return "$listener_rc"
        fi
      }

      remove_listener_address() {
        remove_address=$1
        if listener_present "$remove_address"; then
          rpc nvmf_subsystem_remove_listener ${lib.escapeShellArg modelsNqn} \
            -t rdma -f ipv4 -a "$remove_address" -s 4420 >/dev/null
        else
          listener_rc=$?
          [ "$listener_rc" -eq 1 ] || return "$listener_rc"
        fi
      }

      ensure_listener_address() {
        ensure_address=$1
        if listener_present "$ensure_address"; then
          return 0
        else
          listener_rc=$?
          [ "$listener_rc" -eq 1 ] || return "$listener_rc"
          rpc nvmf_subsystem_add_listener ${lib.escapeShellArg modelsNqn} \
            -t rdma -f ipv4 -a "$ensure_address" -s 4420 >/dev/null
        fi
      }

      remove_listener() { remove_listener_address ${lib.escapeShellArg rdmaAddress}; }
      ensure_listener() { ensure_listener_address ${lib.escapeShellArg rdmaAddress}; }

      # Close the listener before observing controller state. This order is the
      # lock: once removal completes no new controller can race a zero count
      # and enter while namespaces are being changed. Two zero observations
      # also catch a connection handshake which was already in flight.
      quiesce_namespaces() {
        reason=$1
        remove_listener
        for _ in 1 2; do
          controllers=$(rpc nvmf_subsystem_get_controllers ${lib.escapeShellArg modelsNqn} \
            | jq -r "length")
          if [ "$controllers" -gt 0 ]; then
            echo "spdk-export: $reason pending but $controllers controller(s) are connected." >&2
            echo "spdk-export: listener is closed; bounce the clients and the retry timer" >&2
            echo "spdk-export: will continue once the controller count reaches zero." >&2
            exit 1
          fi
          sleep 1
        done
      }

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

      if [ -z "$snapshot" ]; then
        remove_listener
        echo "spdk-export: WARNING: no existing models snapshot found; listener is closed" >&2
        echo "spdk-export: preserving the last-known namespace without mutation" >&2
        exit 1
      fi

      snapshot_bdev=$(rpc bdev_get_bdevs -b "$snapshot")
      if ! jq -e '.[0].supported_io_types.write == false' \
        <<<"$snapshot_bdev" >/dev/null; then
        remove_listener
        echo "spdk-export: refusing writable bdev $snapshot; listener is closed" >&2
        echo "spdk-export: preserving the last-known namespace without mutation" >&2
        exit 1
      fi
      snapshot_uuid=$(jq -er '.[0].uuid' <<<"$snapshot_bdev")

      # The two halves of the pin must describe the same object. If they drift,
      # trex would export the named snapshot while clients look for a UUID that
      # is not there, and the failure would appear on the clients rather than
      # here. Refuse instead, and say exactly what to correct.
      if [ "$snapshot_uuid" != ${lib.escapeShellArg modelsSnapshot.uuid} ]; then
        remove_listener
        echo "spdk-export: pin mismatch in spdk-storage-constants.nix." >&2
        echo "spdk-export:   modelsSnapshot.name = ${modelsSnapshot.name}" >&2
        echo "spdk-export:   modelsSnapshot.uuid = ${modelsSnapshot.uuid}" >&2
        echo "spdk-export:   that snapshot's real uuid = $snapshot_uuid" >&2
        echo "spdk-export: listener closed; preserving the last-known namespace" >&2
        exit 1
      fi

      selected_present=$(jq -r --arg nqn ${lib.escapeShellArg modelsNqn} \
        --arg uuid "$snapshot_uuid" '
          any(.[]; .nqn == $nqn and
            any(.namespaces[]?; .bdev_name == $uuid))
        ' <<<"$subsystems")

      # THE DRAIN GUARD. The deployed SPDK 26.01 spdk_tgt SEGV'd in
      # libspdk_bdev_lvol when namespaces were swapped while controllers were
      # connected or connecting -- reproduced twice on 2026-07-31 (00:04 and
      # 00:30, the second taking the whole host down via hung_task_panic).
      # Upgrading to 26.05 does not erase that operational evidence. So:
      # never touch namespaces while anyone is connected. If a swap is pending
      # close the listener first (blocks reconnects), then observe the
      # controller count, and let the retry timer finish the swap once the last
      # controller is gone. Operators bounce the clients (reboot the strix
      # fleet / restart nvme-trex-models); convergence is automatic within a
      # few retry intervals. George's call (2026-07-31): a deliberate client
      # bounce per pin bump beats crashing weirdly.
      needs_swap=false
      [ "$selected_present" != true ] && needs_swap=true
      stale_count=$(jq -r --arg nqn ${lib.escapeShellArg modelsNqn} \
        --arg uuid "$snapshot_uuid" '
          [.[] | select(.nqn == $nqn) | .namespaces[]?
           | select(.bdev_name != $uuid)] | length
        ' <<<"$subsystems")
      [ "$stale_count" -gt 0 ] && needs_swap=true

      if [ "$needs_swap" = true ]; then
        quiesce_namespaces "namespace swap"
        if [ "$selected_present" != true ]; then
          rpc nvmf_subsystem_add_ns ${lib.escapeShellArg modelsNqn} "$snapshot" >/dev/null
        fi
        subsystems=$(rpc nvmf_get_subsystems)
        mapfile -t stale_nsids < <(jq -r --arg nqn ${lib.escapeShellArg modelsNqn} \
          --arg uuid "$snapshot_uuid" '
            .[] | select(.nqn == $nqn) | .namespaces[]?
            | select(.bdev_name != $uuid) | .nsid
          ' <<<"$subsystems")
        for nsid in "''${stale_nsids[@]}"; do
          rpc nvmf_subsystem_remove_ns ${lib.escapeShellArg modelsNqn} "$nsid" >/dev/null
        done
      fi

      ensure_listener
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
    # Unlike Requires, BindsTo also deactivates this successful oneshot when
    # the target disappears. Its timer can then replay the assembly transaction
    # after spdk-tgt restarts instead of leaving stale active/exited state.
    bindsTo = ["spdk-tgt.service"];
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
      # Must cover the worst honest path: 30 s socket wait + a 120 s final
      # attach (which absorbs the RAID + blobstore examine, see above) + the
      # 60 s array wait + ublk setup. Nothing orders boot on this unit, so a
      # generous ceiling costs nothing; a tight one converts a slow-but-
      # succeeding assembly into a spurious failure.
      TimeoutStartSec = "300s";
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
      OnUnitInactiveSec = "10s";
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
    # Follow assembly down so a target crash cannot leave a stale successful
    # export unit which its OnUnitInactiveSec timer will never retry.
    bindsTo = ["spdk-storage-assemble.service"];
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
      OnUnitInactiveSec = "10s";
      AccuracySec = "1s";
      Unit = "spdk-models-export.service";
    };
  };

  # These consumers retain RequiresMountsFor, but they are timer-started rather
  # than members of a boot target. Missing Optane storage makes the service
  # fail and retry without ever making multi-user.target wait.
  #
  # qBittorrent's own service/timer pair was removed here on 2026-08-09: it now
  # runs inside the arr-servers container, and merely *declaring*
  # systemd.services.qbittorrent on the host instantiated a unit for a service
  # that no longer exists there. The container timer below already gates on the
  # same Optane mount, and the container's own systemd starts qBittorrent once
  # nspawn has bound /var/lib/qbittorrent/incomplete into it.
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
