{ config, pkgs, lib, ... }:

{
  networking.hostName = "odroid-hc1";
  nix.buildCores = 6;

  imports = [
    ../common.nix
  ];

}
