{ config, pkgs, lib, ... }:

{
  networking.hostName = "odroid-hc1";
  nix.buildCores = 6;

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

  imports = [
    ../common.nix
  ];

}
