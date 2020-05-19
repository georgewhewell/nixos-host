{ config, pkgs, lib, ... }:

{

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  imports = [
    ../common-arm.nix
  ];

}
