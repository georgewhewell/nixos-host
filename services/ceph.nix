{ config, lib, pkgs, ... }:

{

  security.acme.certs."ceph.tsar.su" = {
      email = "georgerw@gmail.com";
      webroot = "/var/www/challenges/";
      extraDomains = {
        "musicowl.ceph.tsar.su" = null;
      };
  };

  services.nginx.httpConfig = ''
    server {
       listen 80;
       server_name musicowl.ceph.tsar.su ceph.tsar.su;

       location /.well-known/acme-challenge/ {
           alias /var/www/challenges/.well-known/acme-challenge/;
       }

       location / {
         add_header Strict-Transport-Security "max-age=31536000";
         rewrite ^(.*) https://$host$1 permanent;
       }
    }

    server {
        listen 127.0.0.1:443 ssl;
        server_name ceph.tsar.su musicowl.ceph.tsar.su;

        ssl_certificate /var/lib/acme/ceph.tsar.su/fullchain.pem;
        ssl_certificate_key /var/lib/acme/ceph.tsar.su/key.pem;
        ssl_session_cache shared:SSL:128m;
        ssl_session_timeout 10m;
        
        client_max_body_size 1G;
        dav_methods PUT;

        location / {
            proxy_set_header Host $host;
            proxy_pass http://localhost:8050;
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
        -e CEPH_NETWORK=172.17.0.1/32 \
        -e RGW_CIVETWEB_PORT=8050 \
        ceph/demo
        '';
    };
  };

}
