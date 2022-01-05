{ config, lib, pkgs, ... }:

{

  services.nginx.httpConfig = ''
    server {
       listen 80;
       server_name sentry.tsar.su;

       location /.well-known/acme-challenge/ {
           alias /var/www/challenges/.well-known/acme-challenge/;
       }

       location / {
         rewrite ^(.*) https://$host$1 permanent;
       }
    }

    server {
        listen 127.0.0.1:443 ssl;
        server_name sentry.tsar.su;

        ssl_certificate /var/lib/acme/sentry.tsar.su/fullchain.pem;
        ssl_certificate_key /var/lib/acme/sentry.tsar.su/key.pem;
        ssl_session_cache shared:SSL:128m;
        ssl_session_timeout 10m;

        proxy_set_header   Host                 $http_host;
        proxy_set_header   X-Forwarded-Proto    $scheme;
        proxy_set_header   X-Forwarded-For      $remote_addr;
        proxy_redirect     off;

        # keepalive + raven.js is a disaster
        keepalive_timeout 0;

        # use very aggressive timeouts
        proxy_read_timeout 15s;
        proxy_send_timeout 15s;
        send_timeout 15s;
        resolver_timeout 15s;
        client_body_timeout 15s;

        # buffer larger messages
        client_max_body_size 5m;
        client_body_buffer_size 100k;

        location / {
          proxy_pass        http://localhost:9000;
          add_header Strict-Transport-Security "max-age=31536000";
        }
    }
  '';

  systemd.services.sentry_web = {
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
        -p 127.0.0.1:9000:9000 \
        -e SENTRY_URL_PREFIX=https://sentry.tsar.su \
        -e SENTRY_REDIS_HOST=172.17.0.1 \
        -e SENTRY_POSTGRES_HOST=172.17.0.1 \
        -e SENTRY_DB_USER=sentry \
        -e SENTRY_DB_NAME=sentry \
        -e SENTRY_DB_PASSWORD=sentry \
        -e SENTRY_SECRET_KEY=sentry \
        sentry run web'';
    };
  };

  systemd.services.sentry_worker = {
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
        -e SENTRY_URL_PREFIX=https://sentry.tsar.su \
        -e SENTRY_REDIS_HOST=172.17.0.1 \
        -e SENTRY_POSTGRES_HOST=172.17.0.1 \
        -e SENTRY_DB_USER=sentry \
        -e SENTRY_DB_NAME=sentry \
        -e SENTRY_DB_PASSWORD=sentry \
        -e SENTRY_SECRET_KEY=sentry \
        sentry run worker'';
    };
  };

  systemd.services.sentry_cron = {
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
        -e SENTRY_URL_PREFIX=https://sentry.tsar.su \
        -e SENTRY_REDIS_HOST=172.17.0.1 \
        -e SENTRY_POSTGRES_HOST=172.17.0.1 \
        -e SENTRY_DB_USER=sentry \
        -e SENTRY_DB_NAME=sentry \
        -e SENTRY_DB_PASSWORD=sentry \
        -e SENTRY_SECRET_KEY=sentry \
        sentry run cron'';
    };
  };

}
