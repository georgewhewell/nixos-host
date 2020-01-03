{ config, pkgs, lib, ... }:

{

  imports = [
    ../../../profiles/common.nix
    ../../../profiles/development.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/graphical.nix
    ../../../profiles/g_ether.nix
  ];

  fileSystems."/boot" =
    { device = "/dev/disk/by-label/EFI";
      fsType = "vfat";
    };

  fileSystems."/" =
    { device = "zpool/root/nixos";
      fsType = "zfs";
    };

  networking = {
    hostName = "nixos";
    hostId = "deadbeef";
    useDHCP = true;
    enableIPv6 = false;
    firewall = {
      enable = true;
      allowPing = false;
    };
  };

  time.timeZone = "Europe/London";

  environment.systemPackages = with pkgs; [
    libreoffice
  ];

  virtualisation.virtualbox.guest.enable = true;

}
