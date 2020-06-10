{ config, lib, pkgs, ... }:

{
  security.acme.certs."jupyter.tsar.su" = {
    email = "georgerw@gmail.com";
    webroot = "/var/www/challenges/";
  };

  services.nginx.httpConfig = ''

    server {
       listen 80;
       server_name jupyter.tsar.su;

       location /.well-known/acme-challenge/ {
           alias /var/www/challenges/.well-known/acme-challenge/;
       }

       location / {
         rewrite ^(.*) https://$host$1 permanent;
       }
    }

    server {
        listen 127.0.0.1:443 ssl;
        server_name jupyter.tsar.su;

        ssl_certificate /var/lib/acme/jupyter.tsar.su/fullchain.pem;
        ssl_certificate_key /var/lib/acme/jupyter.tsar.su/key.pem;
        ssl_session_cache shared:SSL:128m;
        ssl_session_timeout 10m;

        location / {
            proxy_pass http://127.0.0.1:8888;

            proxy_set_header        Host            $host;
            proxy_set_header        X-Real-IP       $remote_addr;
            proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header        X-Forwarded-Proto $scheme;
            proxy_redirect     off;

            add_header Strict-Transport-Security "max-age=31536000";
           proxy_set_header X-NginX-Proxy true;

            # WebSocket support
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_read_timeout 86400;
        }
    }
  '';

  systemd.services.jupyter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull jupyter/scipy-notebook''
        ''-${pkgs.docker}/bin/docker rm -f jupyter''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --name jupyter \
        --publish 127.0.0.1:8888:8888 \
        -e PASSWORD="blahg" \
        jupyter/scipy-notebook'';
      ExecStop = ''${pkgs.docker}/bin/docker stop jupyter'';
    };
  };

}
