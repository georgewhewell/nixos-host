{ config, pkgs, lib, ... }:

{
  networking.hostName = "odroid-hc1";
  nix.buildCores = 6;

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

  hardware.deviceTree = {
    enable = true;
    name = "exynos5422-odroidhc1.dtb";
  };

  imports = [
    ../common.nix
  ];

}
