{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 80 443 2222 ];

  security.acme.certs."tsar.su" = {
      email = "georgerw@gmail.com";
      webroot = "/var/www/challenges/";
  };

  services.nginx.enable = true;
  services.nginx.httpConfig = ''
    server {
       listen 80 default;
       server_name tsar.su;

       location /.well-known/acme-challenge/ {
           alias /var/www/challenges/.well-known/acme-challenge/;
       }

       location / {
         rewrite ^(.*) https://$host$1 permanent;
       }
    }
    server {
      listen 82 default;

      location /basic_status {
          stub_status;
      }
    }
  '';
}
