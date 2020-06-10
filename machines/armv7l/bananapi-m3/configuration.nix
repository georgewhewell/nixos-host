{ config, pkgs, lib, ... }:

{

  networking.hostName = "bananapi-m3";
  nix.buildCores = 6;

  imports = [
    ../common.nix
  ];

}
