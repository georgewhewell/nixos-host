{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 80 443 2222 ];

  services.nginx.enable = true;
  services.nginx.httpConfig = ''
    server {
        listen 80 default;
        listen 443 ssl;

        server_name tsar.su www.tsar.su;

        ssl_certificate /etc/letsencrypt/live/git.tsar.su/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/keys/0011_key-letsencrypt.pem;

        root /var/www/munin;

        location / {
          add_header Strict-Transport-Security "max-age=31536000";
        }
    }
  '';
}
