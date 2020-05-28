{ config, pkgs, lib, ... }:

{

  networking.hostName = "orangepi-prime";
  boot.kernelParams = [ "cma=384M" ];
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_megous;

  boot.kernelPatches = [
     {
       name = "media";
       patch = null;
       extraConfig = ''
         STAGING_MEDIA y
       '';
     }
  ];
  
  imports = [
    ../common.nix
    ../../../profiles/tvbox.nix
  ];
}
