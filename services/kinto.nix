{ config, lib, pkgs, ... }:

{
  services.nginx.httpConfig = ''

    server {
      listen 80;
      server_name kinto.tsar.su;

      location / {
          proxy_pass http://127.0.0.1:3232/;

          proxy_set_header        Host            $host;
          proxy_set_header        X-Real-IP       $remote_addr;
          proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header        X-Forwarded-Proto $scheme;
          proxy_redirect          off;
      }
    }
  '';

  systemd.services.kinto = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull kinto/kinto-server''
        ''-${pkgs.docker}/bin/docker stop kinto''
        ''-${pkgs.docker}/bin/docker rm kinto''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --name kinto \
        -p 127.0.0.1:3232:8888 \
        kinto/kinto-server'';
      ExecStop = ''${pkgs.docker}/bin/docker stop kinto'';
    };
  };

}
