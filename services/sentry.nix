{ config, lib, pkgs, ... }:

{
  services.nginx.httpConfig = ''
    server {
       listen 80;
       server_name sentry.tsar.su;
       rewrite ^(.*) https://$host$1 permanent;
    }

    server {
        listen 443 ssl;
        server_name sentry.tsar.su;

        ssl_certificate /etc/letsencrypt/live/git.tsar.su/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/keys/0011_key-letsencrypt.pem;
        ssl_session_cache shared:SSL:128m;
        ssl_session_timeout 10m;
        
        proxy_set_header   Host                 $http_host;
        proxy_set_header   X-Forwarded-Proto    $scheme;
        proxy_set_header   X-Forwarded-For      $remote_addr;
        proxy_redirect     off;

        # keepalive + raven.js is a disaster
        keepalive_timeout 0;

        # use very aggressive timeouts
        proxy_read_timeout 5s;
        proxy_send_timeout 5s;
        send_timeout 5s;
        resolver_timeout 5s;
        client_body_timeout 5s;

        # buffer larger messages
        client_max_body_size 5m;
        client_body_buffer_size 100k;

        location / {
          proxy_pass        http://localhost:9000;
          add_header Strict-Transport-Security "max-age=31536000";
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
        -p 127.0.0.1:9000:9000 \
        -e SENTRY_REDIS_HOST=172.17.42.1 \
        -e SENTRY_POSTGRES_HOST=172.17.42.1 \
        -e SENTRY_DB_USER=sentry \
        -e SENTRY_DB_NAME=sentry \
        -e SENTRY_DB_PASSWORD=sentry \
        sentry'';
      ExecStop = ''${pkgs.docker}/bin/docker stop sentry'';
    };
  };

  systemd.services."sentry-beat" = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull sentry''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --rm \
        -e SENTRY_REDIS_HOST=172.17.42.1 \
        -e SENTRY_POSTGRES_HOST=172.17.42.1 \
        -e SENTRY_DB_NAME=sentry \
        -e SENTRY_DB_USER=sentry \
        -e SENTRY_DB_PASSWORD=sentry \
        sentry sentry celery beat'';
    };
  };

  systemd.services."sentry-worker" = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --rm \
        -e SENTRY_REDIS_HOST=172.17.42.1 \
        -e SENTRY_POSTGRES_HOST=172.17.42.1 \
        -e SENTRY_DB_NAME=sentry \
        -e SENTRY_DB_USER=sentry \
        -e SENTRY_DB_PASSWORD=sentry \
        sentry sentry celery worker'';
    };
  };

}
