{ config, lib, pkgs, ... }:

{
  services.nginx.httpConfig = ''
    server {
        listen 80;
        server_name registry.tsar.su;

        location / {
            proxy_pass http://127.0.0.1:8002/;

            proxy_set_header        Accept-Encoding   "";
            proxy_set_header        Host            $host;
            proxy_set_header        X-Real-IP       $remote_addr;
            proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header        X-Forwarded-Proto $scheme;
            proxy_redirect          off;
        }
    }
  '';

  systemd.services.registry = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull registry:2''
        ''-${pkgs.docker}/bin/docker stop registry''
        ''-${pkgs.docker}/bin/docker rm registry''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --name registry \
        -p 8002:5000 \
        registry:2'';
      ExecStop = ''${pkgs.docker}/bin/docker stop registry'';
    };
  };

}
