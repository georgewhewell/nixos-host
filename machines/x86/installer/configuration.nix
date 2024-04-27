{ config, lib, pkgs, ... }:

{
  imports = [
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix>
    <nixpkgs/nixos/modules/installer/cd-dvd/channel.nix>
    ../../../profiles/common.nix
    ../../../profiles/thinkpad.nix
  ];

  boot.initrd.supportedFilesystems = [
    "zfs"
    "nfs"
    "f2fs"
    "bcachefs"
  ];

  environment.systemPackages = with pkgs; [
    nfsUtils

    cryptsetup
    openssl
    parted
    pbkdf2Sha512
    yubikey-personalization
  ];

  hardware.enableAllFirmware = true;
  networking.wireless.enable = false;

  networking = {
    hostName = "nixos-installer";
    networkmanager = {
      enable = true;
      wifi = {
        backend = "iwd";
      };
    };
  };

  hardware.bluetooth.enable = true;
  services.usbmuxd.enable = true;
  services.fwupd.enable = true;

  documentation.enable = lib.mkDefault false;
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

}
