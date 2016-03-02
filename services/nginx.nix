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
    server {
        listen 443 ssl default;
        server_name tsar.su;

        ssl_certificate /var/lib/acme/tsar.su/fullchain.pem;
        ssl_certificate_key /var/lib/acme/tsar.su/key.pem;
        ssl_session_cache shared:SSL:128m;
        ssl_session_timeout 10m;

        location / {
            proxy_pass http://127.0.0.1:8005;

            proxy_set_header        Host            $host;
            proxy_set_header        X-Real-IP       $remote_addr;
            proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header        X-Forwarded-Proto $scheme;
            proxy_redirect     off;

            add_header Strict-Transport-Security "max-age=31536000";
        }
    }
  '';
}
