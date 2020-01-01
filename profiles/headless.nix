{ config, lib, pkgs, ... }:

{

  sound.enable = lib.mkDefault false;
  services.xserver.enable = false;

}
