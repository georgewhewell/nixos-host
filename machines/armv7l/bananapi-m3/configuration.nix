{ config, pkgs, lib, ... }:

{

  networking.hostName = "bananapi-m3";
  nix.buildCores = 6;

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_allwinner;

  imports = [
    ../common.nix
  ];

}
