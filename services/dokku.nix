{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 22222 ];

  services.nginx.httpConfig = ''

    server {
       listen 80;
       server_name .apps.tsar.su;
       rewrite ^(.*) https://$host$1 permanent;
    }

    server {
        listen 443 ssl;
        server_name .apps.tsar.su;

        ssl_certificate /etc/letsencrypt/live/git.tsar.su/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/keys/0011_key-letsencrypt.pem;
        ssl_session_cache shared:SSL:128m;
        ssl_session_timeout 10m;

        location / {
            proxy_pass http://127.0.0.1:8082/;

            proxy_set_header        Host            $host;
            proxy_set_header        X-Real-IP       $remote_addr;
            proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header        X-Forwarded-Proto $scheme;
            proxy_redirect          off;

            add_header Strict-Transport-Security "max-age=31536000";
        }
    }
  '';

  systemd.services.dokku = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull eugeneware/dokku-in-docker''
        ''-${pkgs.docker}/bin/docker stop dokku''
        ''-${pkgs.docker}/bin/docker rm dokku''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --name dokku \
        --privileged \
        -e VHOSTNAME=apps.tsar.su \
        -e USERNAME=grw \
        -e PUBKEY='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDW9YJVC34+IfBRAMhwtiENOJfUd00jsQhoFMBrGWPclniC1iyxxWpyAXSlvVrIKqxRxoK55Pz9bg3eId5H0iybFIukta+AcWrI6Ny2s0O1f/Q6tv93NPKvVEo+tPwarsEDuwxSGlernBuYa35G6popuRsn//seuQ/hIHneoOIAtG6wGJ38kqT+iKHCCJBfY1c6Hcw09rbm4NBpwbBONhSW9MAQa34mt41jBXmwmsZVEA0fQVuDZtb9PDgc8+ciks75b5Li3WWxo1BP3+A/vAQhat0JRicSa4JXCJs+cadIXoIHvlsYyJZKUXJXDciGkRaV/lYtQZlzvGgy5dtsnlFl' \
        -p 22222:22 \
        -p 8082:80 \
        eugeneware/dokku-in-docker'';
      ExecStop = ''${pkgs.docker}/bin/docker stop dokku'';
    };
  };

}
