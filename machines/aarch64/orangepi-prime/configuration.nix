{ config, pkgs, lib, ... }:

{

  networking.hostName = "orangepi-prime";

  imports = [
    ../common.nix
    ../../../profiles/tvbox.nix
  ];
}
