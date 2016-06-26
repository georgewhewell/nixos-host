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
        listen 127.0.0.1:443 ssl;
        server_name drone.tsar.su;

        ssl_certificate /var/lib/acme/drone.tsar.su/fullchain.pem;
        ssl_certificate_key /var/lib/acme/drone.tsar.su/key.pem;
        ssl_session_cache shared:SSL:128m;
        ssl_session_timeout 10m;

        location / {
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Host $http_host;
    proxy_set_header Origin "";

    proxy_pass http://127.0.0.1:8005;
    proxy_redirect off;
    proxy_http_version 1.1;
    proxy_buffering off;

    chunked_transfer_encoding off;

            add_header Strict-Transport-Security "max-age=31536000";
        }
    }
  '';

  environment.etc.dronerc.text = ''
DATABASE_DRIVER=postgres
DATABASE_CONFIG=postgres://drone:drone@172.17.0.1:5432/drone_0_5?sslmode=disable
DRONE_GOGS=true
DRONE_GOGS_URL=https://git.tsar.su
DRONE_GOGS_PRIVATE_MODE=true
SERVER_ADDR=0.0.0.0:8005
I_UNDERSTAND_I_AM_USING_AN_UNSTABLE_VERSION=true
I_AGREE_TO_FIX_BUGS_AND_NOT_FILE_BUGS=true
DRONE_AGENT_SECRET=Faed0eiv
DRONE_OPEN=true
DRONE_ADMIN=grw
'';

  systemd.services.drone = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull drone/drone:0.5''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --rm \
        --privileged \
        --volume /var/lib/drone:/var/lib/drone \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        --env-file /etc/dronerc \
        --publish 127.0.0.1:8005:8000 \
        drone/drone:0.5'';
      ExecStop = ''${pkgs.docker}/bin/docker rm -f drone'';
    };
  };
environment.etc.droneworkerrc.text = ''
DRONE_TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0ZXh0IjoiRmFlZDBlaXYiLCJ0eXBlIjoiYWdlbnQifQ.-fLSoVrTQLpRSV0L0zJZIPB1Y56Bnw3hppTF75HFEPY
DRONE_SERVER=http://127.0.0.1:8005
DRONE_DEBUG=true
'';

  systemd.services.droneagent = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull drone/drone:0.5''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --rm \
        --privileged \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        --env-file /etc/droneworkerrc \
        --net=host \
        drone/drone:0.5 agent'';
    };
  };
}
