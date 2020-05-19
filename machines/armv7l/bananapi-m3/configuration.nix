{ config, pkgs, lib, ... }:

{

  networking.hostName = "bananapi-m3";

  imports = [
    ../common.nix
  ];

}
