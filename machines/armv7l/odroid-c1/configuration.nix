{ config, pkgs, lib, ... }:

{

  networking.hostName = "odroid-c1";

  imports = [
    ../common.nix
  ];

}
