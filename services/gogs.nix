{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 2222 ];

  services.nginx.httpConfig = ''

    server {
       listen 80;
       server_name git.tsar.su;
       rewrite ^(.*) https://$host$1 permanent;
    }

    server {
        listen 443 ssl;
        server_name git.tsar.su;

        ssl_certificate /etc/letsencrypt/live/git.tsar.su/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/keys/0011_key-letsencrypt.pem;
        ssl_session_cache shared:SSL:128m;
        ssl_session_timeout 10m;

        location / {
            proxy_pass http://127.0.0.1:3000/;

            proxy_set_header        Host            $host;
            proxy_set_header        X-Real-IP       $remote_addr;
            proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header        X-Forwarded-Proto $scheme;
            proxy_redirect          off;

            add_header Strict-Transport-Security "max-age=31536000";
        }
    }
  '';

  systemd.services.gogs = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull gogs/gogs''
        ''-${pkgs.docker}/bin/docker stop gogs''
        ''-${pkgs.docker}/bin/docker rm gogs''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --name gogs \
        -p 127.0.0.1:3000:3000 \
        -p 0.0.0.0:2222:22 \
        -v /mnt/gogs:/data \
        gogs/gogs'';
      ExecStop = ''${pkgs.docker}/bin/docker stop gogs'';
    };
  };

}
