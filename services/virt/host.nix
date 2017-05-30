{ config, lib, pkgs, ... }:

{
  # Turn on virt
  virtualisation.libvirtd.enable = true;
}
