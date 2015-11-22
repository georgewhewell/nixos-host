{ config, lib, pkgs, ... }:

{
  services.nginx.httpConfig = ''
    server {
        listen 80;
        server_name drone.tsar.su;

        location / {
            proxy_pass http://127.0.0.1:8000/;

            proxy_set_header        Accept-Encoding   "";
            proxy_set_header        Host            $host;
            proxy_set_header        X-Real-IP       $remote_addr;
            proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header        X-Forwarded-Proto $scheme;
            proxy_redirect     off;
        }
    }
  '';

  environment.etc."drone/dronerc" = ''
DATABASE_DRIVER=postgres
DATABASE_CONFIG=postgres://drone:drone@localhost:5432/drone?sslmode=disable
REMOTE_DRIVER=gogs
REMOTE_CONFIG=http://git.tsar.su?open=false
  '';

  systemd.services.gogs = {
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
        --volume /var/lib/drone:/var/lib/drone \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        --env-file /etc/drone/dronerc \
        --publish 8000:8000 \
        gogs/gogs'';
      ExecStop = ''${pkgs.docker}/bin/docker stop gogs'';
    };
  };

}
