{ config, lib, pkgs, ... }:

{
  services.nginx.enable = true;
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
