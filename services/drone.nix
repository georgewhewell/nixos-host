{ config, lib, pkgs, ... }:

{
  security.acme.certs."drone.tsar.su" = {
      email = "georgerw@gmail.com";
      webroot = "/var/www/challenges/";
  };
  
  services.nginx.httpConfig = ''

    server {
       listen 80;
       server_name drone.tsar.su;

       location /.well-known/acme-challenge/ {
           alias /var/www/challenges/.well-known/acme-challenge/;
       }

       location / {
         rewrite ^(.*) https://$host$1 permanent;
       }
    }

    server {
        listen 443 ssl;
        server_name drone.tsar.su;

        ssl_certificate /var/lib/acme/drone.tsar.su/fullchain.pem;
        ssl_certificate_key /var/lib/acme/drone.tsar.su/key.pem;
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

  environment.etc.dronerc.text = ''
DATABASE_DRIVER=postgres
DATABASE_CONFIG=postgres://drone:drone@172.17.0.1:5432/drone?sslmode=disable
REMOTE_DRIVER=gogs
REMOTE_CONFIG=https://git.tsar.su?open=false
SERVER_ADDR=0.0.0.0:8005
'';

  systemd.services.drone = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull drone/drone:0.4''
        ''-${pkgs.docker}/bin/docker stop drone''
        ''-${pkgs.docker}/bin/docker rm drone''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --name drone \
        --privileged \
        --volume /var/lib/drone:/var/lib/drone \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        --env-file /etc/dronerc \
        --publish 127.0.0.1:8005:8005 \
        drone/drone:0.4'';
      ExecStop = ''${pkgs.docker}/bin/docker stop drone'';
    };
  };

}
