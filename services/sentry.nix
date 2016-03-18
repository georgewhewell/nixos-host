{ config, lib, pkgs, ... }:

{

  security.acme.certs."sentry.tsar.su" = {
      email = "georgerw@gmail.com";
      webroot = "/var/www/challenges/";
  };

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
        ''-${pkgs.docker}/bin/docker rm -f sentry''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --name sentry \
        -p 127.0.0.1:9000:9000 \
        -e SENTRY_URL_PREFIX=https://sentry.tsar.su \
        -e SENTRY_REDIS_HOST=172.17.0.1 \
        -e SENTRY_POSTGRES_HOST=172.17.0.1 \
        -e SENTRY_DB_USER=sentry \
        -e SENTRY_DB_NAME=sentry \
        -e SENTRY_DB_PASSWORD=sentry \
        -e SENTRY_SECRET_KEY=sentry \
        sentry'';
      ExecStop = ''${pkgs.docker}/bin/docker rm -f sentry'';
    };
  };
  systemd.services.sentry_workers = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull sentry''
        ''-${pkgs.docker}/bin/docker rm -f sentry_workers''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --name sentry_workers \
        -e SENTRY_URL_PREFIX=https://sentry.tsar.su \
        -e SENTRY_REDIS_HOST=172.17.0.1 \
        -e SENTRY_POSTGRES_HOST=172.17.0.1 \
        -e SENTRY_DB_USER=sentry \
        -e SENTRY_DB_NAME=sentry \
        -e SENTRY_DB_PASSWORD=sentry \
        -e SENTRY_SECRET_KEY=sentry \
        sentry sentry celery worker -B -c 4'';
      ExecStop = ''${pkgs.docker}/bin/docker rm -f sentry_workers'';
    };
  };
}
