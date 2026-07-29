{
  lib,
  pkgs,
  ...
}: let
  arrayName = "optane-stripe";
  arrayDevice = "/dev/mapper/${arrayName}";
  volumeGroup = "optane";
  modelsLogicalVolume = "models";
  modelsLogicalDevice = "/dev/${volumeGroup}/${modelsLogicalVolume}";
  modelsFilesystemUuid = "7bda5ad7-77af-4a25-8a44-9f5f2d75d067";
  nixLogicalVolume = "nix";
  nixLogicalDevice = "/dev/${volumeGroup}/${nixLogicalVolume}";
  nixFilesystemUuid = "31d96c77-d1ca-4961-9eb3-7ee3b0bd5fd0";

  # Eight Intel Optane 905P 1.5 TB namespaces. Identity is tied to the NVMe
  # serial, never the controller number or PCI bus address.
  memberSerials = [
    "PHKE336401D81P5CGN"
    "PHKE336401G31P5CGN"
    "PHKE336400TZ1P5CGN"
    "PHKE336401F31P5CGN"
    "PHKE336400RU1P5CGN"
    "PHKE3351006G1P5CGN"
    "PHKE336401Q61P5CGN"
    "PHKE336401L81P5CGN"
  ];

  # Each namespace contains 2,930,277,168 512-byte sectors. A striped target
  # must end on a full 64 KiB chunk on every member, leaving the final 48
  # sectors unused.
  memberSectors = 2930277120;
  arraySectors = memberSectors * builtins.length memberSerials;
  stripSectors = 128;
  modelsLogicalSectors = 8589934592; # 4 TiB
  nixLogicalSectors = 2147483648; # 1 TiB

  assemble = pkgs.writeShellApplication {
    name = "optane-dm-stripe-assemble";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.lvm2
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      set -eu

      find_member() {
        local expected_serial="$1"
        local controller controller_name model observed_serial namespace

        for controller in /sys/class/nvme/nvme[0-9]*; do
          [ -r "$controller/serial" ] || continue
          observed_serial="$(tr -d ' \n' < "$controller/serial")"
          [ "$observed_serial" = "$expected_serial" ] || continue

          model="$(tr -d ' \n' < "$controller/model")"
          [ "$model" = INTELSSDPE21D015TA ] || {
            echo "optane-dm: serial $expected_serial has unexpected model $model" >&2
            return 1
          }

          controller_name="''${controller##*/}"
          namespace="$controller/$controller_name"n1
          [ -b "/dev/''${namespace##*/}" ] || return 1
          printf '/dev/%s\n' "''${namespace##*/}"
          return 0
        done
        return 1
      }

      udevadm settle

      members=()
      ${lib.concatMapStringsSep "\n" (serial: ''
          member=
          for _ in $(seq 1 120); do
            member="$(find_member ${lib.escapeShellArg serial} || true)"
            [ -n "$member" ] && break
            sleep 1
          done
          [ -n "$member" ] || {
            echo "optane-dm: NVMe controller ${serial} did not appear" >&2
            exit 1
          }
          members+=("$member")
        '')
        memberSerials}

      [ "''${#members[@]}" -eq 8 ] || {
        echo "optane-dm: found ''${#members[@]} members, expected 8" >&2
        exit 1
      }

      table=${lib.escapeShellArg "0 ${toString arraySectors} striped 8 ${toString stripSectors}"}
      canonical_table="$table"
      for member in "''${members[@]}"; do
        sectors="$(blockdev --getsz "$member")"
        [ "$sectors" -eq 2930277168 ] || {
          echo "optane-dm: $member has $sectors sectors, expected 2930277168" >&2
          exit 1
        }
        table="$table $member 0"
        major_minor="$(lsblk -dnro MAJ:MIN "$member")"
        canonical_table="$canonical_table $major_minor 0"
      done

      if dmsetup info ${lib.escapeShellArg arrayName} >/dev/null 2>&1; then
        observed_table="$(dmsetup table ${lib.escapeShellArg arrayName})"
        [ "$observed_table" = "$canonical_table" ] || {
          echo "optane-dm: existing ${arrayName} has unexpected geometry" >&2
          echo "expected: $canonical_table" >&2
          echo "observed: $observed_table" >&2
          exit 1
        }
      else
        dmsetup create ${lib.escapeShellArg arrayName} --table "$table"
      fi

      udevadm settle
      [ "$(blockdev --getsz ${lib.escapeShellArg arrayDevice})" -eq ${toString arraySectors} ] || {
        echo "optane-dm: ${arrayDevice} has an unexpected size" >&2
        exit 1
      }
      [ "$(blockdev --getro ${lib.escapeShellArg arrayDevice})" -eq 0 ] || {
        echo "optane-dm: ${arrayDevice} is unexpectedly read-only" >&2
        exit 1
      }

      observed_vg="$(
        pvs \
          --devices ${lib.escapeShellArg arrayDevice} \
          --noheadings \
          --options vg_name \
          ${lib.escapeShellArg arrayDevice} |
          xargs
      )"
      [ "$observed_vg" = ${lib.escapeShellArg volumeGroup} ] || {
        echo "optane-dm: ${arrayDevice} belongs to VG $observed_vg, expected ${volumeGroup}" >&2
        exit 1
      }

      vgchange \
        --devices ${lib.escapeShellArg arrayDevice} \
        --activate y \
        ${lib.escapeShellArg volumeGroup}
      udevadm settle

      validate_lv() {
        local device="$1"
        local expected_sectors="$2"
        local expected_uuid="$3"
        local observed_uuid

        [ -b "$device" ] || {
          echo "optane-dm: $device did not activate" >&2
          return 1
        }
        [ "$(blockdev --getsz "$device")" -eq "$expected_sectors" ] || {
          echo "optane-dm: $device has an unexpected size" >&2
          return 1
        }

        observed_uuid="$(blkid -s UUID -o value "$device" 2>/dev/null || true)"
        [ "$observed_uuid" = "$expected_uuid" ] || {
          echo "optane-dm: $device has filesystem UUID $observed_uuid, expected $expected_uuid" >&2
          return 1
        }
      }

      validate_lv \
        ${lib.escapeShellArg modelsLogicalDevice} \
        ${toString modelsLogicalSectors} \
        ${lib.escapeShellArg modelsFilesystemUuid}
      validate_lv \
        ${lib.escapeShellArg nixLogicalDevice} \
        ${toString nixLogicalSectors} \
        ${lib.escapeShellArg nixFilesystemUuid}
    '';
  };

  disassemble = pkgs.writeShellApplication {
    name = "optane-dm-stripe-disassemble";
    runtimeInputs = [
      pkgs.lvm2
      pkgs.util-linux
    ];
    text = ''
      set -eu

      if dmsetup info ${lib.escapeShellArg arrayName} >/dev/null 2>&1; then
        if findmnt -rn -S ${lib.escapeShellArg modelsLogicalDevice} >/dev/null ||
          findmnt -rn -S ${lib.escapeShellArg nixLogicalDevice} >/dev/null; then
          echo "optane-dm: refusing to deactivate a mounted Optane LV" >&2
          exit 1
        fi

        if pvs \
          --devices ${lib.escapeShellArg arrayDevice} \
          --noheadings \
          --options vg_name \
          ${lib.escapeShellArg arrayDevice} 2>/dev/null |
          grep -qw ${lib.escapeShellArg volumeGroup}; then
          vgchange \
            --devices ${lib.escapeShellArg arrayDevice} \
            --activate n \
            ${lib.escapeShellArg volumeGroup}
        fi

        dmsetup remove --retry ${lib.escapeShellArg arrayName}
      fi
    '';
  };
in {
  # The 905Ps are ordinary kernel NVMe devices. Device mapper provides the
  # RAID0-equivalent mapping without userspace pollers or dedicated CPU cores.
  boot.kernelModules = [
    "nvme"
    "dm_mod"
  ];
  boot.initrd.kernelModules = [
    "nvme"
    "dm_mod"
  ];

  systemd.services.optane-dm-stripe = {
    description = "64 KiB dm-stripe across the eight Optane 905Ps";
    wantedBy = ["multi-user.target"];
    after = [
      "systemd-modules-load.service"
      "systemd-udev-settle.service"
    ];
    before = ["nix.mount"];
    wants = ["systemd-udev-settle.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${assemble}/bin/optane-dm-stripe-assemble";
      ExecStop = "${disassemble}/bin/optane-dm-stripe-disassemble";
      RemainAfterExit = true;
      TimeoutStartSec = "180s";
      TimeoutStopSec = "120s";
    };
  };

  boot.initrd.systemd.services.optane-dm-stripe = {
    description = "Assemble the Optane dm-stripe and activate its LVM volumes";
    requiredBy = ["sysroot-nix.mount"];
    before = ["sysroot-nix.mount"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${assemble}/bin/optane-dm-stripe-assemble";
      RemainAfterExit = true;
      TimeoutStartSec = "180s";
    };
  };

  systemd.mounts = [
    {
      description = "XFS models filesystem on the Optane LVM volume";
      what = "/dev/disk/by-uuid/${modelsFilesystemUuid}";
      where = "/mnt/optane/models";
      type = "xfs";
      options = "noatime";
      unitConfig.DefaultDependencies = false;
      wantedBy = ["multi-user.target"];
      requires = ["optane-dm-stripe.service"];
      after = ["optane-dm-stripe.service"];
      bindsTo = ["optane-dm-stripe.service"];
      conflicts = ["umount.target"];
      before = ["umount.target"];
    }
  ];

  systemd.tmpfiles.rules = ["d /mnt/optane 0755 root root -"];

  environment.systemPackages = [
    pkgs.lvm2
    pkgs.xfsprogs
  ];

  # /nix-on-LVM migration disabled 2026-07-29: requires the 905P array present at
  # every boot, and the shelf is currently detached. The data copy on the nix LV
  # remains valid; re-enable this block once the array is back and verified.
  # fileSystems."/nix" = {
  #   device = lib.mkForce "/dev/disk/by-uuid/${nixFilesystemUuid}";
  #   fsType = lib.mkForce "xfs";
  #   neededForBoot = true;
  #   # mkForce would discard the x-initrd.mount that neededForBoot injects,
  #   # leaving stage-1 unable to mount /nix on the tmpfs root (2026-07-28 outage)
  #   options = lib.mkForce ["noatime" "x-initrd.mount"];
  # };

  assertions = [
    {
      assertion = builtins.length memberSerials == 8;
      message = "Trex Optane dm-stripe must contain exactly eight controllers";
    }
    {
      assertion = builtins.length (lib.unique memberSerials) == builtins.length memberSerials;
      message = "Trex Optane dm-stripe controller serials must be unique";
    }
  ];
}
