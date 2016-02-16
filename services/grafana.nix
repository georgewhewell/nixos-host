{ config, lib, pkgs, ... }:

{
  services.nginx.httpConfig = ''

    server {
        listen 80;
        server_name grafana.tsar.su;

        location / {
            proxy_pass http://127.0.0.1:3001/;

            proxy_set_header        Host            $host;
            proxy_set_header        X-Real-IP       $remote_addr;
            proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header        X-Forwarded-Proto $scheme;
            proxy_redirect          off;
        }
    }
  '';

  systemd.services.grafana = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull georgewhewell/docker-grafana-influx-dashboard''
        ''-${pkgs.docker}/bin/docker rm -f grafana''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --name grafana \
        -p 127.0.0.1:3001:3001 \
        georgewhewell/docker-grafana-influx-dashboard'';
      ExecStop = ''${pkgs.docker}/bin/docker stop grafana'';
    };
  };

}
