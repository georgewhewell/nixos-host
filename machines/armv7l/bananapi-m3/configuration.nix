{ config, pkgs, lib, ... }:

{

  networking.hostName = "bananapi-m3";
  nix.buildCores = 7;

  imports = [
    ../common.nix
  ];

}
