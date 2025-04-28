{...}: let
  lanIp = "192.168.23.1";
in {
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # Create MongoDB init script
  environment.etc."mongodb-init/init-mongo.sh" = {
    mode = "0755";
    text = ''
      #!/bin/bash
      if which mongosh > /dev/null 2>&1; then
        mongo_init_bin='mongosh'
      else
        mongo_init_bin='mongo'
      fi

      "$mongo_init_bin" <<EOF
      use admin
      db.auth("$MONGO_INITDB_ROOT_USERNAME", "$MONGO_INITDB_ROOT_PASSWORD")
      db.createUser({
        user: "$MONGO_USER",
        pwd: "$MONGO_PASS",
        roles: [
          { db: "$MONGO_DBNAME", role: "dbOwner" },
          { db: "$MONGO_DBNAME_stat", role: "dbOwner" }
        ]
      })
      EOF
    '';
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      unifi-db = {
        image = "docker.io/mongo:4.4";
        environment = {
          MONGO_INITDB_ROOT_USERNAME = "root";
          MONGO_INITDB_ROOT_PASSWORD = "your_root_password_here";
          MONGO_USER = "unifi";
          MONGO_PASS = "your_unifi_password_here";
          MONGO_DBNAME = "unifi";
          MONGO_AUTHSOURCE = "admin";
        };
        volumes = [
          "/var/lib/unifi-db:/data/db"
          "/etc/mongodb-init/init-mongo.sh:/docker-entrypoint-initdb.d/init-mongo.sh:ro"
        ];
        extraOptions = [
          "--network=bridge"
        ];
      };

      unifi = {
        image = "lscr.io/linuxserver/unifi-network-application:latest";
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = "Etc/UTC";
          MONGO_USER = "unifi";
          MONGO_PASS = "your_unifi_password_here";
          MONGO_HOST = "unifi-db";
          MONGO_PORT = "27017";
          MONGO_DBNAME = "unifi";
          MONGO_AUTHSOURCE = "admin";
        };
        volumes = [
          "/var/lib/unifi:/config"
        ];
        extraOptions = [
          "--network=bridge"
          "-p"
          "${lanIp}:8443:8443"
          "-p"
          "${lanIp}:3478:3478/udp"
          "-p"
          "${lanIp}:10001:10001/udp"
          "-p"
          "${lanIp}:8080:8080"
          "-p"
          "${lanIp}:8843:8843"
          "-p"
          "${lanIp}:8880:8880"
          "-p"
          "${lanIp}:6789:6789"
          "-p"
          "${lanIp}:5514:5514/udp"
        ];
        dependsOn = ["unifi-db"];
      };
    };
  };

  # Create persistent volume directories
  systemd.tmpfiles.rules = [
    "d /var/lib/unifi 0755 root root -"
    "d /var/lib/unifi-db 0755 root root -"
  ];

  # Add firewall rules for LAN access only
  networking.firewall.interfaces."tap0" = {
    allowedTCPPorts = [
      8443 # Web UI
      8080 # Device communication
      8843 # HTTPS redirect
      8880 # HTTP portal
      6789 # Speed test
    ];
    allowedUDPPorts = [
      3478 # STUN
      10001 # Device discovery
      5514 # Remote syslog
    ];
  };
}
