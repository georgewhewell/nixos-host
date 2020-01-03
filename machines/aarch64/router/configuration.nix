{ config, pkgs, lib, ... }:

{
  networking.hostName = "router";

  boot.initrd.availableKernelModules = [ "dwmac-sun8i" ];

  imports = [
    ../common.nix
    ../../../profiles/router.nix
  ];
}
