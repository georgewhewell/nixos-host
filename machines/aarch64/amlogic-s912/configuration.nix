{ config, pkgs, lib, ... }:

{
  networking.hostName = "amlogic-s912";
  boot.kernelParams = [ "cma=786M" ];

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
  hardware.firmware = with pkgs; [ meson-firmware armbian-firmware ];

  # make /dev/dri0 be panfrost?
  boot.initrd.availableKernelModules = [ "panfrost" ];

  boot.kernelPatches = (lib.mapAttrsToList (name: _: {
      name = "${name}";
      patch = "${pkgs.sources."LibreELEC.tv"}/projects/Amlogic/patches/linux/${name}";
  })
  (builtins.readDir "${pkgs.sources."LibreELEC.tv"}/projects/Amlogic/patches/linux"));

  imports = [
    ../common.nix
    ../../../profiles/nas-mounts.nix
    ../../../profiles/tvbox-gbm.nix
  ];
}
