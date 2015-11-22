{ config, lib, pkgs, ... }:

{
  services.nginx.enable = true;
 # services.nginx.config = pkgs.lib.readFile /etc/nixos/services/nginx/nginx.conf;
  services.nginx.httpConfig = ''
    include /etc/nixos/services/nginx/*.nginx;
  '';	

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
