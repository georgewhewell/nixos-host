{ config, pkgs, lib, ... }:

{

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
  boot.kernelPatches = [
    {
      name = "rock64-1.5ghz";
      patch = ../../packages/patches/RK3328-enable-1512mhz-opp.patch;
    }
  ];

  imports = [
    ../common-arm.nix
  ];

}
