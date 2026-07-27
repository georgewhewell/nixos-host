{
  config,
  lib,
  pkgs,
  ...
}: let
  spdk = pkgs.spdk-ublk;
  rpc = "${spdk}/bin/spdk-rpc";
  rpcSocket = "/run/spdk/spdk.sock";

  # These are the eight directly attached Intel Optane 905P controllers.
  # Keep the PCI allowlist as well as the expected serials: the allowlist
  # prevents SPDK from probing unrelated VFIO devices, while the serial audit
  # makes accidental controller replacement visible before storage is mounted.
  optanes = [
    {
      name = "Optane0";
      memberName = "OptaneMember0";
      memberUuid = "c04744b3-b1be-4e2c-b6d8-93d19ab58a59";
      bdf = "0000:01:00.0";
      serial = "PHKE336401D81P5CGN";
    }
    {
      name = "Optane1";
      memberName = "OptaneMember1";
      memberUuid = "ae86c273-72ba-45f2-9609-76470157ab45";
      bdf = "0000:02:00.0";
      serial = "PHKE336401G31P5CGN";
    }
    {
      name = "Optane2";
      memberName = "OptaneMember2";
      memberUuid = "0a012edc-cc7b-48f4-b40c-695e85e8fa7e";
      bdf = "0000:03:00.0";
      serial = "PHKE336400TZ1P5CGN";
    }
    {
      name = "Optane3";
      memberName = "OptaneMember3";
      memberUuid = "81800417-7ea5-41c9-99e8-2113e2a7fb4b";
      bdf = "0000:04:00.0";
      serial = "PHKE336401F31P5CGN";
    }
    {
      name = "Optane4";
      memberName = "OptaneMember4";
      memberUuid = "15de20c3-0833-487f-8676-271f047fc2d6";
      bdf = "0000:41:00.0";
      serial = "PHKE336400RU1P5CGN";
    }
    {
      name = "Optane5";
      memberName = "OptaneMember5";
      memberUuid = "514976bf-390a-4218-ab3d-ad9e362f5d3a";
      bdf = "0000:42:00.0";
      serial = "PHKE3351006G1P5CGN";
    }
    {
      name = "Optane6";
      memberName = "OptaneMember6";
      memberUuid = "bee9c32c-372e-480e-ae91-28117342cf8a";
      bdf = "0000:43:00.0";
      serial = "PHKE336401Q61P5CGN";
    }
    {
      name = "Optane7";
      memberName = "OptaneMember7";
      memberUuid = "e257e9d1-005c-4ac4-b8b8-3dcd1f8f13cb";
      bdf = "0000:44:00.0";
      serial = "PHKE336401L81P5CGN";
    }
  ];

  raidName = "OptaneRaid0";
  raidUuid = "1650b5f0-66d0-4268-b463-c513259aaa8b";
  lvolStoreName = "optane";
  lvolStoreUuid = "ae304f5a-7e17-4d97-8c44-5ccf7290effd";

  # Adding a volume here exports the existing SPDK lvol as /dev/ublkb<ID>
  # and mounts its XFS filesystem. Creation and formatting remain an explicit,
  # manual provisioning operation; boot must never manufacture storage.
  #
  volumes.models = {
    id = 0;
    mountPoint = "/mnt/optane/models";
    mountUnit = "mnt-optane-models.mount";
    lvolUuid = "2f5eaa6d-aafe-4b69-94e0-026a1a0eca62";
    fsUuid = "2c83b49a-2daf-45c9-8f36-1d3f230022f4";
    sizeBytes = 4398046511104;
    allocatedClusters = 1048576;
  };

  volumeList =
    lib.mapAttrsToList
    (name: volume:
      volume
      // {
        inherit name;
        bdevName = "${lvolStoreName}/${name}";
        device = "/dev/ublkb${toString volume.id}";
        fsDevice = "/dev/disk/by-uuid/${volume.fsUuid}";
      })
    volumes;

  pciAllowArgs =
    lib.concatMapStringsSep " "
    (drive: "-A ${lib.escapeShellArg drive.bdf}")
    optanes;

  validateVfio = pkgs.writeShellApplication {
    name = "spdk-optane-validate-vfio";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      set -eu

      ${lib.concatMapStringsSep "\n" (drive: ''
          bdf=${lib.escapeShellArg drive.bdf}
          device="/sys/bus/pci/devices/$bdf"

          [ -d "$device" ] || {
            echo "spdk-optane: expected PCI controller $bdf is absent" >&2
            exit 1
          }
          [ "$(cat "$device/vendor")" = 0x8086 ] || {
            echo "spdk-optane: $bdf has unexpected vendor $(cat "$device/vendor")" >&2
            exit 1
          }
          [ "$(cat "$device/device")" = 0x2700 ] || {
            echo "spdk-optane: $bdf has unexpected device $(cat "$device/device")" >&2
            exit 1
          }

          driver="$(basename "$(readlink -f "$device/driver")")"
          [ "$driver" = vfio-pci ] || {
            echo "spdk-optane: $bdf is owned by $driver, expected vfio-pci" >&2
            exit 1
          }

          iommu_group="$(readlink -f "$device/iommu_group")"
          members="$(find "$iommu_group/devices" -mindepth 1 -maxdepth 1 | wc -l)"
          [ "$members" -eq 1 ] || {
            echo "spdk-optane: $bdf IOMMU group has $members members, expected one" >&2
            exit 1
          }
        '')
        optanes}
    '';
  };

  assemble = pkgs.writeShellApplication {
    name = "spdk-optane-assemble";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      set -eu

      rpc() {
        ${rpc} -s ${lib.escapeShellArg rpcSocket} "$@"
      }

      ready=false
      for _ in $(seq 1 60); do
        if rpc rpc_get_methods >/dev/null 2>&1; then
          ready=true
          break
        fi
        sleep 0.5
      done
      [ "$ready" = true ] || {
        echo "spdk-optane: SPDK RPC socket did not become ready" >&2
        exit 1
      }

      # The physical namespaces have no persistent NVMe UUID, so SPDK assigns
      # a different UUID after every daemon restart. Prevent the RAID module
      # from examining those transient identities; fixed-UUID passthrough
      # bdevs below are the persistent RAID members.
      rpc bdev_set_options --no-auto-examine >/dev/null
      rpc framework_start_init >/dev/null
      rpc framework_wait_init >/dev/null

      ${lib.concatMapStringsSep "\n" (drive: ''
          controller=${lib.escapeShellArg drive.name}
          expected_bdf=${lib.escapeShellArg drive.bdf}
          expected_serial=${lib.escapeShellArg drive.serial}
          member=${lib.escapeShellArg drive.memberName}
          member_uuid=${lib.escapeShellArg drive.memberUuid}

          observed_bdf="$(
            rpc bdev_nvme_get_controllers \
              | jq -r --arg name "$controller" \
                  '.[] | select(.name == $name) | .ctrlrs[0].trid.traddr // empty'
          )"

          if [ -z "$observed_bdf" ]; then
            rpc bdev_nvme_attach_controller \
              -b "$controller" \
              -t PCIe \
              -a "$expected_bdf" >/dev/null
          elif [ "$observed_bdf" != "$expected_bdf" ]; then
            echo "spdk-optane: $controller points at $observed_bdf, expected $expected_bdf" >&2
            exit 1
          fi

          bdev="$controller"n1
          details="$(rpc bdev_get_bdevs -b "$bdev" -t 10000)"
          observed_serial="$(
            printf '%s\n' "$details" \
              | jq -r '.[0].driver_specific.nvme[0].ctrlr_data.serial_number // empty' \
              | tr -d ' '
          )"
          if [ -n "$observed_serial" ] && [ "$observed_serial" != "$expected_serial" ]; then
            echo "spdk-optane: $expected_bdf has serial $observed_serial, expected $expected_serial" >&2
            exit 1
          fi

          member_details="$(
            rpc bdev_get_bdevs \
              | jq -c --arg name "$member" \
                  '.[] | select(.name == $name)'
          )"
          if [ -z "$member_details" ]; then
            rpc bdev_passthru_create \
              -b "$bdev" \
              -p "$member" \
              -u "$member_uuid" >/dev/null
          elif [ "$(printf '%s\n' "$member_details" | jq -r '.uuid')" != "$member_uuid" ]; then
            echo "spdk-optane: $member has an unexpected UUID" >&2
            exit 1
          fi
        '')
        optanes}

      ${lib.concatMapStringsSep "\n" (drive: ''
          rpc bdev_examine -b ${lib.escapeShellArg drive.memberName} >/dev/null
        '')
        optanes}
      rpc bdev_wait_for_examine >/dev/null

      raid_ready=false
      for _ in $(seq 1 60); do
        if rpc bdev_get_bdevs \
          | jq -e --arg name ${lib.escapeShellArg raidName} \
              '.[] | select(.name == $name)' >/dev/null
        then
          raid_ready=true
          break
        fi
        sleep 0.5
      done
      [ "$raid_ready" = true ] || {
        echo "spdk-optane: persistent RAID ${raidName} was not discovered" >&2
        exit 1
      }

      raid="$(
        rpc bdev_raid_get_bdevs all \
          | jq -e --arg name ${lib.escapeShellArg raidName} \
              '.[] | select(.name == $name)'
      )"
      [ "$(printf '%s\n' "$raid" | jq -r '.uuid')" = ${lib.escapeShellArg raidUuid} ] || {
        echo "spdk-optane: ${raidName} has an unexpected UUID" >&2
        exit 1
      }
      [ "$(printf '%s\n' "$raid" | jq -r '.raid_level')" = raid0 ] || {
        echo "spdk-optane: ${raidName} is not RAID0" >&2
        exit 1
      }
      [ "$(printf '%s\n' "$raid" | jq -r '.strip_size_kb')" = 64 ] || {
        echo "spdk-optane: ${raidName} does not use the declared 64 KiB strip" >&2
        exit 1
      }
      [ "$(printf '%s\n' "$raid" | jq '.base_bdevs_list | length')" -eq 8 ] || {
        echo "spdk-optane: ${raidName} does not have eight members" >&2
        exit 1
      }
      [ "$(printf '%s\n' "$raid" | jq -r '.num_base_bdevs_operational')" -eq 8 ] || {
        echo "spdk-optane: ${raidName} does not have eight operational members" >&2
        exit 1
      }
      [ "$(printf '%s\n' "$raid" | jq -r '.superblock')" = true ] || {
        echo "spdk-optane: ${raidName} does not have persistent superblocks enabled" >&2
        exit 1
      }

      rpc bdev_examine -b ${lib.escapeShellArg raidName} >/dev/null
      rpc bdev_wait_for_examine >/dev/null
      rpc bdev_lvol_get_lvstores \
        | jq -e --arg name ${lib.escapeShellArg lvolStoreName} \
            --arg uuid ${lib.escapeShellArg lvolStoreUuid} \
            --arg base ${lib.escapeShellArg raidName} \
            '.[] | select(
              .name == $name
              and .uuid == $uuid
              and .base_bdev == $base
              and .cluster_size == 4194304
            )' >/dev/null \
        || {
          echo "spdk-optane: lvolstore ${lvolStoreName} on ${raidName} was not discovered" >&2
          exit 1
        }
    '';
  };

  startUblk = pkgs.writeShellApplication {
    name = "spdk-optane-start-ublk";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      set -eu

      rpc() {
        ${rpc} -s ${lib.escapeShellArg rpcSocket} "$@"
      }

      # ublk_get_disks returns an empty list both before target creation and
      # for an initialized target with no disks. A normal service restart runs
      # ExecStop first, so create the target only when no exported disk exists.
      existing_disks="$(rpc ublk_get_disks 2>/dev/null || printf '[]\n')"
      if [ "$(printf '%s\n' "$existing_disks" | jq 'length')" -eq 0 ]; then
        rpc ublk_create_target -m 0xff00000000000000 >/dev/null 2>&1 || true
      fi

      ${lib.concatMapStringsSep "\n" (volume: ''
          expected_bdev=${lib.escapeShellArg volume.bdevName}
          expected_lvol_uuid=${lib.escapeShellArg volume.lvolUuid}
          expected_fs_uuid=${lib.escapeShellArg volume.fsUuid}
          expected_size=${toString volume.sizeBytes}
          expected_allocated_clusters=${toString volume.allocatedClusters}
          ublk_id=${toString volume.id}

          details="$(
            rpc bdev_get_bdevs \
              | jq -ce \
                  --arg alias "$expected_bdev" \
                  --arg uuid "$expected_lvol_uuid" \
                  '.[] | select(
                    .uuid == $uuid
                    and (.name == $uuid or (.aliases // [] | index($alias)))
                  )'
          )"
          observed_size="$(
            printf '%s\n' "$details" | jq -r '.block_size * .num_blocks'
          )"
          [ "$observed_size" -eq "$expected_size" ] || {
            echo "spdk-optane: $expected_bdev is $observed_size bytes, expected $expected_size" >&2
            exit 1
          }
          rpc bdev_lvol_get_lvols \
            | jq -e \
                --arg alias "$expected_bdev" \
                --arg uuid "$expected_lvol_uuid" \
                --argjson clusters "$expected_allocated_clusters" \
                '.[] | select(
                  .alias == $alias
                  and .uuid == $uuid
                  and .is_thin_provisioned == false
                  and .num_allocated_clusters == $clusters
                )' >/dev/null \
            || {
              echo "spdk-optane: $expected_bdev is not the declared thick lvol" >&2
              exit 1
            }

          existing="$(
            rpc ublk_get_disks \
              | jq -r --argjson id "$ublk_id" \
                  '.[] | select(.id == $id) | .bdev_name // empty'
          )"
          if [ -z "$existing" ]; then
            rpc ublk_start_disk "$expected_bdev" "$ublk_id" \
              -q 8 \
              -d 256 >/dev/null
          elif [ "$existing" != "$expected_bdev" ] && [ "$existing" != "$expected_lvol_uuid" ]; then
            echo "spdk-optane: ublk $ublk_id exports $existing, expected $expected_bdev ($expected_lvol_uuid)" >&2
            exit 1
          fi

          for _ in $(seq 1 60); do
            [ -b ${lib.escapeShellArg volume.device} ] && break
            sleep 0.5
          done
          [ -b ${lib.escapeShellArg volume.device} ] || {
            echo "spdk-optane: ${volume.device} did not appear" >&2
            exit 1
          }

          observed_fs_uuid="$(
            blkid -s UUID -o value ${lib.escapeShellArg volume.device} 2>/dev/null || true
          )"
          [ "$observed_fs_uuid" = "$expected_fs_uuid" ] || {
            echo "spdk-optane: ${volume.device} has filesystem UUID $observed_fs_uuid, expected $expected_fs_uuid" >&2
            exit 1
          }

          udevadm settle
          for _ in $(seq 1 60); do
            [ -b ${lib.escapeShellArg volume.fsDevice} ] && break
            sleep 0.5
          done
          [ -b ${lib.escapeShellArg volume.fsDevice} ] || {
            echo "spdk-optane: ${volume.fsDevice} did not appear" >&2
            exit 1
          }
          [ "$(readlink -f ${lib.escapeShellArg volume.fsDevice})" = ${lib.escapeShellArg volume.device} ] || {
            echo "spdk-optane: ${volume.fsDevice} does not resolve to ${volume.device}" >&2
            exit 1
          }
        '')
        volumeList}
    '';
  };

  stopUblk = pkgs.writeShellApplication {
    name = "spdk-optane-stop-ublk";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      set -u

      rpc() {
        ${rpc} -s ${lib.escapeShellArg rpcSocket} "$@"
      }

      ${lib.concatMapStringsSep "\n" (volume: ''
          rpc ublk_stop_disk ${toString volume.id} >/dev/null 2>&1 || true
        '')
        (lib.reverseList volumeList)}
      rpc ublk_destroy_target >/dev/null 2>&1 || true
      exit 0
    '';
  };

  mountUnits =
    map (volume: {
      description = "XFS on SPDK lvol ${volume.bdevName}";
      what = volume.fsDevice;
      where = volume.mountPoint;
      type = "xfs";
      options = "noatime";
      wantedBy = ["multi-user.target"];
      requires = ["spdk-optane-ublk.service"];
      after = ["spdk-optane-ublk.service"];
      bindsTo = ["spdk-optane-ublk.service"];
    })
    volumeList;
in {
  # Reserve the 905Ps before the kernel NVMe driver can expose their stale
  # swap/ZFS signatures. The two P1600X boot drives and four Corsair drives
  # have different PCI IDs and remain on the kernel nvme driver.
  boot.initrd.kernelModules = ["vfio_pci"];
  boot.kernelParams = ["vfio-pci.ids=8086:2700"];
  boot.kernelModules = ["ublk_drv"];

  environment.systemPackages = [
    spdk
    assemble
    validateVfio
    pkgs.xfsprogs
  ];

  systemd.services.spdk-optane-target = {
    description = "SPDK target for the eight Optane 905P controllers";
    wantedBy = ["multi-user.target"];
    requires = ["dev-hugepages1G.mount"];
    after = [
      "dev-hugepages1G.mount"
      "systemd-modules-load.service"
    ];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = "${validateVfio}/bin/spdk-optane-validate-vfio";
      ExecStart = "${spdk}/bin/spdk_tgt --wait-for-rpc -m 0xff00000000000000 -p 56 -s 1024 --huge-dir /dev/hugepages1G -r ${rpcSocket} ${pciAllowArgs}";
      ExecStartPost = "${assemble}/bin/spdk-optane-assemble";
      RuntimeDirectory = "spdk";
      RuntimeDirectoryMode = "0750";
      LimitMEMLOCK = "infinity";
      TimeoutStartSec = "120s";
      TimeoutStopSec = "120s";
    };
  };

  systemd.services.spdk-optane-ublk = lib.mkIf (volumeList != []) {
    description = "Export Optane SPDK lvols through ublk";
    wantedBy = ["multi-user.target"];
    requires = ["spdk-optane-target.service"];
    after = ["spdk-optane-target.service"];
    bindsTo = ["spdk-optane-target.service"];
    before = map (volume: volume.mountUnit) volumeList;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${startUblk}/bin/spdk-optane-start-ublk";
      ExecStop = "${stopUblk}/bin/spdk-optane-stop-ublk";
      RemainAfterExit = true;
      TimeoutStartSec = "120s";
      TimeoutStopSec = "120s";
    };
  };

  systemd.mounts = mountUnits;

  systemd.tmpfiles.rules =
    ["d /mnt/optane 0755 root root -"]
    ++ map (volume: "d ${volume.mountPoint} 0755 root root -") volumeList;

  assertions = [
    {
      assertion = lib.length optanes == 8;
      message = "Trex SPDK Optane array must contain exactly eight controllers";
    }
    {
      assertion =
        lib.length (lib.unique (map (volume: volume.id) volumeList))
        == lib.length volumeList;
      message = "Trex SPDK Optane ublk IDs must be unique";
    }
    {
      assertion =
        lib.length (lib.unique (map (volume: volume.mountPoint) volumeList))
        == lib.length volumeList;
      message = "Trex SPDK Optane mount points must be unique";
    }
  ];
}
