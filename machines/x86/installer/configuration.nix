{ config, lib, pkgs, ...}:

{
  imports = [
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix>
    <nixpkgs/nixos/modules/installer/cd-dvd/channel.nix>
    ../../../profiles/common.nix
  ];

  boot.initrd.supportedFilesystems = [
    "zfs"
    "nfs"
    "f2fs"
  ];

  environment.systemPackages = with pkgs; [
    nfsUtils
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

  boot.kernelModules = [ "wl" ];
  boot.blacklistedKernelModules = [
    "b44" "b43" "b43legacy" "ssb" "brcmsmac" "bcma" ];
  boot.extraModulePackages = [
    config.boot.kernelPackages.broadcom_sta
  ];

  documentation.enable = lib.mkDefault false;
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

}
