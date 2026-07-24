# Documentation-grade disko layout for the trex root pair (2026-07-24).
# NOT applied with disko-install: the ESPs predate this layout and carry the
# old zfs-root generations as a boot fallback, so the live btrfs partitions
# were cut by hand (sfdisk) around them. This declaration is for a future
# destructive rebuild of both disks, not for the current cutover.
#
# Disks: 2x Intel Optane P1600X 118G (SSDPEK1A118GA), native 4Kn.
#   p1: 4G ESP (TREXBOOTA / TREXBOOTB, pre-existing, mirrored by
#       boot.loader.systemd-boot.extraInstallCommands)
#   p2: btrfs "trexroot" member — sectorsize 4096, data raid0 (~212G),
#       metadata raid1, subvols /nix and /persist, mounted
#       compress=zstd,noatime,flushoncommit. Root itself is tmpfs.
{
  disk1 ? "/dev/disk/by-id/nvme-INTEL_SSDPEK1A118GA_PHOC331301BP118B",
  disk2 ? "/dev/disk/by-id/nvme-INTEL_SSDPEK1A118GA_PHOC331301BN118B",
  ...
}: let
  mkDisk = name: vfatLabel: device: btrfsContent: {
    type = "disk";
    inherit device;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          label = "trex-${name}-ESP";
          size = "4G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            extraArgs = ["-F" "32" "-n" vfatLabel];
          };
        };
        root = {
          label = "trex-root-${name}";
          size = "100%";
          content = btrfsContent;
        };
      };
    };
  };
  btrfs = {
    type = "btrfs";
    # Disko creates/formats disks in attribute-name order. trex-boot-a's root
    # partition therefore exists before this filesystem is made on
    # trex-boot-b, and joins as mkfs.btrfs's second device.
    extraArgs = [
      "-f"
      "-L"
      "trexroot"
      "-s"
      "4096"
      "-d"
      "raid0"
      "-m"
      "raid1"
      "/dev/disk/by-partlabel/trex-root-a"
    ];
    subvolumes = {
      "/nix" = {
        mountpoint = "/nix";
        mountOptions = ["compress=zstd" "noatime" "flushoncommit"];
      };
      "/persist" = {
        mountpoint = "/persist";
        mountOptions = ["compress=zstd" "noatime" "flushoncommit"];
      };
    };
  };
in {
  disko.devices = {
    disk = {
      trex-boot-a = mkDisk "a" "TREXBOOTA" disk1 null;
      trex-boot-b = mkDisk "b" "TREXBOOTB" disk2 btrfs;
    };
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = ["mode=755" "size=16G"];
    };
  };
}
