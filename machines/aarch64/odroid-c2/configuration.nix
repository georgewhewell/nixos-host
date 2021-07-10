{ config, pkgs, lib, ... }:

{
  networking.hostName = "odroid-c2";

  imports = [
    ../common.nix
    ../../../services/tvheadend.nix
  ];
}
