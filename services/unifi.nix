{ config, lib, pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;
  services.unifi.enable = true;
  networking.firewall.allowedTCPPorts = [ 8443 ];
}
