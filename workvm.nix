{ config, pkgs, lib, ... }:

{

  fileSystems."/boot" =
    { device = "/dev/disk/by-label/EFI";
      fsType = "vfat";
    };

  fileSystems."/" =
    { device = "zpool/root/nixos";
      fsType = "zfs";
    };

  networking.hostName = "nixos";
  networking.hostId = "deadbeef";

  networking.firewall = {
    enable = true;
    allowPing = false;
  };

  time.timeZone = "Europe/London";

  boot.initrd.supportedFilesystems = [ "zfs" ];
  # List packages installed in system profile. To search by name, run:
  environment.systemPackages = with pkgs; [
    libreoffice
    firefox
  ];

  nix.maxJobs = lib.mkDefault 2;
  virtualisation.virtualbox.guest.enable = true;

  imports = [
    ./profiles/common.nix
    ./profiles/development.nix
    ./profiles/gpg-yubikey.nix
    ./profiles/uefi-boot.nix
    ./profiles/xserver.nix
  ];
}
