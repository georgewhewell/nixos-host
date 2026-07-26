{ lib, ... }:
{
  # A self-contained local-boot image for recovering strix-2 when firmware
  # network boot is unavailable. 13 GiB fits the 14,403,239,936-byte USB/NVMe
  # bridge currently used for recovery while leaving enough room for the
  # production closure on a compressed btrfs root.
  disko.imageBuilder = {
    name = "strix-2-nvme";
    copyNixStoreThreads = 8;
  };

  disko.devices.disk.strix-2-nvme = {
    type = "disk";
    device = "/dev/nvme0n1";
    imageName = "strix-2-nvme";
    imageSize = "13G";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          name = "strix-2-ESP";
          start = "1M";
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            extraArgs = [ "-F" "32" "-n" "STRIX2ESP" ];
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          name = "strix-2-root";
          size = "100%";
          type = "8304";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" "-L" "strix-2-root" ];
            subvolumes."@root" = {
              mountpoint = "/";
              mountOptions = [
                "compress=zstd:1"
                "discard=async"
                "noatime"
              ];
            };
          };
        };
      };
    };
  };

  # The image is copied to a larger NVMe in normal use. Grow the root
  # partition and filesystem explicitly after the first successful boot;
  # keeping image-time resizing disabled makes the artifact deterministic.
  systemd.services.strix-grow-root.enable = lib.mkForce false;
}
