{ config, lib, pkgs, ...}:

{
  imports = [
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/router.nix
    ../../../profiles/uefi-boot.nix
  ];

  fileSystems."/" =
    { device = "/dev/sda1";
      fsType = "ext4";
    };

  # does not boot without hdmi connected in uefi mode D:
  boot.loader = {
    systemd-boot.enable = lib.mkForce false;
    grub = {
      configurationLimit = 10;
      device = "/dev/sda";
    };
  };

  boot.supportedFilesystems = lib.mkForce [ "ext4" ];
  boot.initrd.supportedFilesystems = lib.mkForce [ "ext4" ];

  networking = {
    hostName = "router";
    wlanInterfaces = {
      wlan-private = {
        device = "wlp2s0";
      };
    };
  };

}
