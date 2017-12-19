{ config, lib, pkgs, ... }:

{
  # Turn on virt
  virtualisation.libvirtd.enable = true;

  /* Constantly complains about missing extension pack
  virtualisation.virtualbox.host.enable = true;
  nixpkgs.config.virtualbox.enableExtensionPack = true;
  */

  environment.systemPackages = with pkgs; [
    virtmanager
  ];
}
