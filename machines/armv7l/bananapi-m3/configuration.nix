{ config, pkgs, lib, ... }:

{
  networking.hostName = "bananapi-m3";
  boot.initrd.availableKernelModules = [ "sunxi" "wire" ];

  imports = [
    ../common.nix
  ];
}
