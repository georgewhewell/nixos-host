{ config, lib, pkgs, ... }:

{
  services.nginx.httpConfig = ''
    server {
        listen 80;
        server_name sentry.tsar.su;

        location / {
            proxy_pass http://127.0.0.1:9000/;

            proxy_set_header        Accept-Encoding   "";
            proxy_set_header        Host            $host;
            proxy_set_header        X-Real-IP       $remote_addr;
            proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header        X-Forwarded-Proto $scheme;
            proxy_redirect          off;
        }
    }
  '';

  systemd.services.sentry = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull sentry''
        ''-${pkgs.docker}/bin/docker stop sentry''
        ''-${pkgs.docker}/bin/docker rm sentry''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --name sentry \
        -p 9000 \
        -e SENTRY_REDIS_HOST=172.17.42.1 \
        -e SENTRY_POSTGRES_HOST=172.17.42.1 \
        -e SENTRY_DB_USER=sentry \
        -e SENTRY_DB_PASSWORD=sentry \
        sentry'';
      ExecStop = ''${pkgs.docker}/bin/docker stop sentry'';
    };
  };

}
