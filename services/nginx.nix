{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  services.nginx.enable = true;
  services.nginx.httpConfig = ''
    server {
        listen 80 default;
        listen 443 ssl default;
        server_name tsar.su www.tsar.su;

        ssl_certificate /etc/nixos/ssl/tsar.pem;
        ssl_certificate_key /etc/nixos/ssl/tsar.key;
        root /var/www/munin;
    }
  '';
}
