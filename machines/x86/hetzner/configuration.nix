{ config, pkgs, lib, modulesPath, ... }:

{

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/headless.nix
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

    deployment.targetHost = "78.47.88.127";
    deployment.targetUser = "root";
    deployment.substituteOnDestination = true;

    networking= {
      hostId = "deadbeef";
      hostName = "cloud";
    };

    boot.loader.grub.device = "/dev/sda";
    boot.loader.systemd-boot.enable = false;

    fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };

}
