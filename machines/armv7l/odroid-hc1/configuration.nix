{ config, pkgs, lib, ... }:

{
  networking.hostName = "odroid-hc1";
  nix.buildCores = 4;

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

  hardware.deviceTree = {
    enable = true;
    name = "exynos5422-odroidhc1.dtb";
  };

  imports = [
    ../common.nix
  ];

}
