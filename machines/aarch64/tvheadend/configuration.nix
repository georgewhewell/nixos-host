{ config, pkgs, lib, ... }:

{
  networking.hostName = "tvheadend";

  imports = [
    ../common.nix
    ../../../services/tvheadend.nix
  ];

}
