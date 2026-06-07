{config, pkgs, network, ...}: let
  lanIp = network.routerIp;
  mongoUser = "unifi";
  mongoPassword = "unifi-local-only";
  mongoRootUser = "root";
  mongoRootPassword = "unifi-root-local-only";
  podman = "${config.virtualisation.podman.package}/bin/podman";
  unifiMongoUri = "mongodb\\://${mongoUser}\\:${mongoPassword}@unifi-db\\:27017/unifi?tls\\=false&authSource\\=admin";
  unifiStatMongoUri = "mongodb\\://${mongoUser}\\:${mongoPassword}@unifi-db\\:27017/unifi_stat?tls\\=false&authSource\\=admin";
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
          { db: "''${MONGO_DBNAME}_stat", role: "dbOwner" },
          { db: "''${MONGO_DBNAME}_audit", role: "dbOwner" }
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
          MONGO_INITDB_ROOT_USERNAME = mongoRootUser;
          MONGO_INITDB_ROOT_PASSWORD = mongoRootPassword;
          MONGO_USER = mongoUser;
          MONGO_PASS = mongoPassword;
          MONGO_DBNAME = "unifi";
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
          MONGO_HOST = "unifi-db";
          MONGO_PORT = "27017";
          MONGO_USER = mongoUser;
          MONGO_PASS = mongoPassword;
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

  systemd.services.podman-unifi = {
    after = ["network-online.target" "unifi-mongo-users.service"];
    wants = ["network-online.target"];
    requires = ["unifi-mongo-users.service"];
    preStart = ''
      props=/var/lib/unifi/data/system.properties
      if [ -e "$props" ]; then
        set_property() {
          key="$1"
          value="$2"
          tmp="$(${pkgs.coreutils}/bin/mktemp)"
          ${pkgs.gawk}/bin/awk -v key="$key" -v value="$value" '
            BEGIN { replaced = 0 }
            $0 ~ "^" key "=" {
              print key "=" value
              replaced = 1
              next
            }
            { print }
            END {
              if (!replaced) {
                print key "=" value
              }
            }
          ' "$props" > "$tmp"
          ${pkgs.coreutils}/bin/cat "$tmp" > "$props"
          ${pkgs.coreutils}/bin/rm -f "$tmp"
        }

        set_property db.mongo.local false
        set_property db.mongo.uri '${unifiMongoUri}'
        set_property statdb.mongo.uri '${unifiStatMongoUri}'
        set_property unifi.db.name unifi
      fi
    '';
  };

  systemd.services.unifi-mongo-users = {
    description = "Ensure UniFi Mongo users exist";
    requires = ["podman-unifi-db.service"];
    after = ["podman-unifi-db.service"];
    before = ["podman-unifi.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.coreutils];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail

      mongo() {
        ${podman} exec unifi-db mongo --quiet "$@"
      }

      for _ in $(seq 1 60); do
        if mongo --eval 'db.adminCommand({ ping: 1 })' >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      ensure_root='
        const admin = db.getSiblingDB("admin");
        const root = admin.getUser("${mongoRootUser}");
        if (root) {
          admin.updateUser("${mongoRootUser}", {
            pwd: "${mongoRootPassword}",
            roles: [{ db: "admin", role: "root" }]
          });
        } else {
          admin.createUser({
            user: "${mongoRootUser}",
            pwd: "${mongoRootPassword}",
            roles: [{ db: "admin", role: "root" }]
          });
        }
      '

      ensure_unifi='
        const admin = db.getSiblingDB("admin");
        const roles = [
          { db: "unifi", role: "dbOwner" },
          { db: "unifi_stat", role: "dbOwner" },
          { db: "unifi_audit", role: "dbOwner" }
        ];
        const unifi = admin.getUser("${mongoUser}");
        if (unifi) {
          admin.updateUser("${mongoUser}", {
            pwd: "${mongoPassword}",
            roles: roles
          });
        } else {
          admin.createUser({
            user: "${mongoUser}",
            pwd: "${mongoPassword}",
            roles: roles
          });
        }
      '

      if ! mongo -u "${mongoRootUser}" -p "${mongoRootPassword}" --authenticationDatabase admin --eval 'db.adminCommand({ ping: 1 })' >/dev/null 2>&1; then
        mongo --eval "$ensure_root"
      fi

      mongo -u "${mongoRootUser}" -p "${mongoRootPassword}" --authenticationDatabase admin --eval "$ensure_unifi"
    '';
  };

  # Add firewall rules for LAN access only
  networking.firewall.interfaces."br0.lan" = {
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
