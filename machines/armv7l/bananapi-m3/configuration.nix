{ config, pkgs, lib, ... }:

{
  networking.hostName = "bananapi-m3";
  boot.initrd.availableKernelModules = [ "dwmac-sun8i" ];

  imports = [
    ../common.nix
  ];
}
