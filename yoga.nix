{ config, pkgs, lib, ... }:

{

  networking.hostName = "yoga";
  networking.hostId = "deadbeef";

  fileSystems."/" =
    { device = "zpool/root/yoga-nixos";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = "/dev/nvme0n1p3";
      fsType = "vfat";
    };

  nix.maxJobs = lib.mkDefault 4;

  services.xserver.dpi = 142;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };
  hardware.sensor.iio.enable = true;

  environment.systemPackages = with pkgs; [
    steam
  ];

  imports =
    [
      ./modules/custom-packages.nix
      ./profiles/common.nix
      ./profiles/development.nix
      ./profiles/xserver.nix
      ./profiles/nas-mounts.nix
      ./profiles/uefi-boot.nix
      ./profiles/thinkpad.nix
      ./profiles/g_ether.nix
    ];

}
