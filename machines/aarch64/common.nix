{ config, pkgs, ... }:

{

  boot.kernelPackages = pkgs.linuxPackages_latest;

  imports = [
    ../common-arm.nix
  ];

}
