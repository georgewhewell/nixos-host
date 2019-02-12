{ config, lib, pkgs, ... }:

{
  # Turn on virt
  virtualisation.libvirtd.enable = true;

  environment.systemPackages = with pkgs; [
    virtmanager
    spice-gtk # fix usb redirect
  ];
}
