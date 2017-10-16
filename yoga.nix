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

  environment.systemPackages = with pkgs; [
    acpi
    git
    vim
    nox
    atom
    chromium
    sway
    alacritty
    xwayland
    modemmanager
    networkmanagerapplet
    psmisc
    psutils
    usbmuxd
    gnupg
  ];

  imports =
    [
      ./profiles/common.nix
      ./profiles/xserver.nix
      ./profiles/nas-mounts.nix
      ./profiles/uefi-boot.nix
      ./profiles/thinkpad.nix
      ./profiles/g_ether.nix
    ];

  networking.bridges."br0" = {
    interfaces = [];
  };

  networking.interfaces."br0" = {
    /*networking.interfaces."usb0" = {*/
    ipAddress = "10.10.10.1";
    prefixLength = 24;
  };

  services.nfs.server = {
    enable = true;
    exports = ''
      /export         *(rw,fsid=0,no_subtree_check)
      /export/store   *(rw,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
    '';
  };

  networking.firewall.allowedTCPPorts = [
    111  # nfs?
    2049
    20048 # nfs
  ];

}
