{ config, pkgs, lib, ... }:

{
  networking.hostName = "odroid-hc1";

  imports = [
    ../common.nix
  ];
}
