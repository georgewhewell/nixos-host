{ config, lib, pkgs, ... }:

{
  services.nginx.enable = true;
  services.nginx.config = pkgs.lib.readFile /etc/nixos/services/nginx/nginx.conf;

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
