{ config, lib, pkgs, ... }:

{
  # Turn on virt
  virtualisation.libvirtd.enable = true;
  /*virtualisation.libvirtd.headless = true;*/
  virtualisation.virtualbox.host.enable = true;
  nixpkgs.config.virtualbox.enableExtensionPack = true;

  environment.systemPackages = with pkgs; [
    virtmanager
  ];
}
