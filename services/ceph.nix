{ config, lib, pkgs, ... }:

{

  security.acme.certs."ceph.tsar.su" = {
      email = "georgerw@gmail.com";
      webroot = "/var/www/challenges/";
  };

  security.acme.certs."musicowl.ceph.tsar.su" = {
      email = "georgerw@gmail.com";
      webroot = "/var/www/challenges/";
  };

  services.nginx.httpConfig = ''
    server {
       listen 80;
       server_name .ceph.tsar.su;

       location /.well-known/acme-challenge/ {
           alias /var/www/challenges/.well-known/acme-challenge/;
       }

       location / {
         rewrite ^(.*) https://$host$1 permanent;
       }
    }

    server {
        listen 127.0.0.1:443 ssl;
        server_name musicowl.ceph.tsar.su;

        ssl_certificate /var/lib/acme/musicowl.ceph.tsar.su/fullchain.pem;
        ssl_certificate_key /var/lib/acme/musicowl.ceph.tsar.su/key.pem;
        ssl_session_cache shared:SSL:128m;
        ssl_session_timeout 10m;

        proxy_set_header   Host                 $http_host;
        proxy_set_header   X-Forwarded-Proto    $scheme;
        proxy_set_header   X-Forwarded-For      $remote_addr;
        proxy_redirect     off;

        client_max_body_size 128m;

        location / {
          proxy_pass        http://localhost:8050;
          add_header Strict-Transport-Security "max-age=31536000";
        }
    }

    server {
        listen 127.0.0.1:443 ssl;
        server_name ceph.tsar.su;

        ssl_certificate /var/lib/acme/ceph.tsar.su/fullchain.pem;
        ssl_certificate_key /var/lib/acme/ceph.tsar.su/key.pem;
        ssl_session_cache shared:SSL:128m;
        ssl_session_timeout 10m;

        proxy_set_header   Host                 $http_host;
        proxy_set_header   X-Forwarded-Proto    $scheme;
        proxy_set_header   X-Forwarded-For      $remote_addr;
        proxy_redirect     off;

        client_max_body_size 128m;

        location / {
          proxy_pass        http://localhost:8050;
          add_header Strict-Transport-Security "max-age=31536000";
        }
    }
  '';

  systemd.services.ceph = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --rm \
        --net=host \
        -v /zpool/ceph/demostack/etc:/etc/ceph \
        -v /zpool/ceph/demostack/ceph:/var/lib/ceph \
        -e MON_IP=176.9.138.4 \
        -e RGW_CIVETWEB_PORT=8050 \
        -e CEPH_NETWORK=172.17.0.1/32 \
        ceph/demo
        '';
    };
  };

}
