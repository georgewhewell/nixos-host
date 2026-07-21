{ config, lib, pkgs, ... }:
let
  cfg = config.services.beegfs-cluster;

  # Classic BeeGFS daemons (meta/storage/client) use `key = value` conf files.
  confFormat = {
    generate = name: settings: pkgs.writeText name (lib.generators.toKeyValue
      {
        mkKeyValue = k: v: "${k} = ${
          if lib.isBool v then lib.boolToString v else toString v}";
      }
      settings);
  };

  tomlFormat = pkgs.formats.toml { };

  # Daemons read the shared connection secret through systemd's credential
  # mechanism so the on-disk secret (e.g. a sops path) only needs to be
  # root-readable.
  credAuthPath = unit: "/run/credentials/${unit}/conn.auth";

  authSettings = unit:
    if cfg.authDisable then {
      connDisableAuthentication = true;
    } else {
      connAuthFile = credAuthPath unit;
    };

  authCredential =
    lib.optional (!cfg.authDisable) "conn.auth:${cfg.connAuthFile}";

  # Hardening shared by all BeeGFS daemons. RDMA (libbeegfs_ib / beegfs.ko
  # userspace peers) needs /dev/infiniband and rdma netlink, so device access
  # is left open and no RestrictAddressFamilies is applied to meta/storage.
  commonHardening = {
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectProc = "invisible";
    LockPersonality = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
    UMask = "0077";
  };

  daemonCommon = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  metaUnit = "beegfs-meta.service";
  storageUnit = "beegfs-storage.service";

  metaConf = confFormat.generate "beegfs-meta.conf" (
    {
      sysMgmtdHost = cfg.mgmtdHost;
      storeMetaDirectory = cfg.meta.directory;
      storeAllowFirstRunInit = cfg.meta.allowFirstRunInit;
      connMetaPort = cfg.meta.port;
      connUseRDMA = cfg.rdma;
      runDaemonized = false;
      logType = "syslog";
    }
    // authSettings metaUnit
    // cfg.meta.settings);

  storageConf = confFormat.generate "beegfs-storage.conf" (
    {
      sysMgmtdHost = cfg.mgmtdHost;
      storeStorageDirectory = lib.concatStringsSep "," cfg.storage.directories;
      storeAllowFirstRunInit = cfg.storage.allowFirstRunInit;
      connStoragePort = cfg.storage.port;
      connUseRDMA = cfg.rdma;
      runDaemonized = false;
      logType = "syslog";
    }
    // authSettings storageUnit
    // cfg.storage.settings);

  clientConf = mount: confFormat.generate "beegfs-client-${mount.name}.conf" (
    {
      sysMgmtdHost = cfg.mgmtdHost;
      connUseRDMA = cfg.rdma;
    }
    # The kernel module reads the conf at mount time as root; point it
    # directly at the (root-readable) secret.
    // (if cfg.authDisable then {
      connDisableAuthentication = true;
    } else {
      connAuthFile = cfg.connAuthFile;
    })
    // mount.settings);

  mgmtdConfFile = tomlFormat.generate "beegfs-mgmtd.toml" cfg.mgmtd.settings;

  anyServerEnabled = cfg.mgmtd.enable || cfg.meta.enable || cfg.storage.enable;
  anyEnabled = anyServerEnabled || cfg.client.enable;
in
{
  options.services.beegfs-cluster = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.beegfs;
      defaultText = lib.literalExpression "pkgs.beegfs";
      description = "BeeGFS userspace package (meta/storage daemons, fsck).";
    };

    ctlPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.beegfs-ctl;
      defaultText = lib.literalExpression "pkgs.beegfs-ctl";
      description = "BeeGFS command-line tool package.";
    };

    mgmtdHost = lib.mkOption {
      type = lib.types.str;
      example = "192.168.23.31";
      description = ''
        Address of the BeeGFS management daemon. Use a literal IP address:
        the client kernel module has no DNS resolver and rejects hostnames
        at mount time (userspace daemons would accept either).
      '';
    };

    connAuthFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/beegfs-conn-auth";
      description = ''
        Path (string, not copied to the store) to the shared connection
        secret. Must hold the same bytes on every node of the cluster.
        Mutually exclusive with {option}`services.beegfs-cluster.authDisable`.
      '';
    };

    authDisable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disable BeeGFS connection authentication entirely.";
    };

    rdma = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use RDMA (RoCE/InfiniBand) for inter-node connections.";
    };

    mgmtd = {
      enable = lib.mkEnableOption "BeeGFS management daemon";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.beegfs-mgmtd;
        defaultText = lib.literalExpression "pkgs.beegfs-mgmtd";
        description = "BeeGFS management daemon package.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8008;
        description = "BeeMsg (TCP+UDP) port.";
      };

      grpcPort = lib.mkOption {
        type = lib.types.port;
        default = 8010;
        description = "gRPC (TCP) port, used by the `beegfs` CTL.";
      };

      tls = {
        certFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            PEM certificate for the gRPC endpoint. When null, TLS is
            disabled (`--tls-disable`) — fine on a trusted LAN, where the
            BeeMsg protocol is unencrypted anyway.
          '';
        };
        keyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "PEM private key belonging to `tls.certFile`.";
        };
      };

      settings = lib.mkOption {
        type = tomlFormat.type;
        default = { };
        description = ''
          Extra mgmtd settings written to beegfs-mgmtd.toml (snake_case
          keys, see `beegfs-mgmtd --help`). Mainly needed for quota and
          capacity-pool tuning.
        '';
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra command-line arguments for beegfs-mgmtd.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the BeeMsg and gRPC ports.";
      };
    };

    meta = {
      enable = lib.mkEnableOption "BeeGFS metadata daemon";

      directory = lib.mkOption {
        type = lib.types.str;
        example = "/var/lib/beegfs/meta";
        description = ''
          Metadata directory. Should live on low-latency storage (metadata
          is extended-attribute heavy; ext4/xfs on NVMe recommended).
        '';
      };

      allowFirstRunInit = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Allow the daemon to initialize an empty metadata directory and
          register with the management daemon on first start. Set to false
          once the cluster is formed.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8005;
        description = "Meta daemon (TCP+UDP) port.";
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf (lib.types.oneOf [ lib.types.bool lib.types.int lib.types.str ]);
        default = { };
        example = { tuneNumWorkers = 32; };
        description = "Extra beegfs-meta.conf settings.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the meta port.";
      };
    };

    storage = {
      enable = lib.mkEnableOption "BeeGFS storage daemon";

      directories = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.str;
        example = [ "/mnt/nvme0/beegfs" ];
        description = "Storage target directories (one per target).";
      };

      allowFirstRunInit = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Allow the daemon to initialize empty storage targets and register
          with the management daemon on first start. Set to false once the
          cluster is formed.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8003;
        description = "Storage daemon (TCP+UDP) port.";
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf (lib.types.oneOf [ lib.types.bool lib.types.int lib.types.str ]);
        default = { };
        description = "Extra beegfs-storage.conf settings.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the storage port.";
      };
    };

    client = {
      enable = lib.mkEnableOption "BeeGFS client (kernel module and mounts)";

      modulePackage = lib.mkOption {
        type = lib.types.package;
        default = config.boot.kernelPackages.callPackage
          ../packages/beegfs/client-module.nix
          { };
        defaultText = lib.literalExpression
          "config.boot.kernelPackages.callPackage ../packages/beegfs/client-module.nix { }";
        description = "beegfs.ko built for the running kernel.";
      };

      mounts = lib.mkOption {
        default = { };
        description = ''
          BeeGFS mounts, keyed by mount point. Each mount gets its own
          client conf file and systemd mount unit.
        '';
        type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
          options = {
            settings = lib.mkOption {
              type = lib.types.attrsOf
                (lib.types.oneOf [ lib.types.bool lib.types.int lib.types.str ]);
              default = { };
              example = { connMaxInternodeNum = 32; };
              description = "Extra beegfs-client.conf settings for this mount.";
            };

            automount = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Start a systemd automount at boot and defer the real BeeGFS
                mount until the path is accessed. This keeps an unavailable
                cluster from delaying boot.
              '';
            };

            idleTimeoutSec = lib.mkOption {
              type = lib.types.str;
              default = "10min";
              description = "Idle timeout for an enabled systemd automount.";
            };

            mountTimeoutSec = lib.mkOption {
              type = lib.types.str;
              default = "45s";
              description = "Maximum time systemd allows the mount operation to run.";
            };
          };
        }));
      };
    };
  };

  config = lib.mkIf anyEnabled {
    assertions = [
      {
        assertion = (cfg.connAuthFile != null) != cfg.authDisable;
        message = ''
          services.beegfs-cluster: set exactly one of connAuthFile (recommended) or
          authDisable = true. BeeGFS refuses to start without an explicit
          authentication decision.
        '';
      }
      {
        assertion = cfg.mgmtd.enable
          -> (cfg.mgmtd.tls.certFile != null) == (cfg.mgmtd.tls.keyFile != null);
        message = "services.beegfs-cluster.mgmtd.tls: certFile and keyFile must be set together.";
      }
    ];

    environment.systemPackages = [ cfg.ctlPackage ]
      # v8 mgmtd is a separate Rust package. Only classic meta/storage roles
      # need the C++ server package in the system closure.
      ++ lib.optional (cfg.meta.enable || cfg.storage.enable) cfg.package;

    ## Management daemon ####################################################

    systemd.services.beegfs-mgmtd = lib.mkIf cfg.mgmtd.enable (daemonCommon // {
      description = "BeeGFS management daemon";
      serviceConfig = commonHardening // {
        Type = "notify";
        DynamicUser = true;
        StateDirectory = "beegfs-mgmtd";
        LoadCredential = authCredential
          ++ lib.optionals (cfg.mgmtd.tls.certFile != null) [
          "cert.pem:${cfg.mgmtd.tls.certFile}"
          "key.pem:${cfg.mgmtd.tls.keyFile}"
        ];
        RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6 AF_NETLINK";
        Restart = "on-failure";
        RestartSec = "5s";
        ExecStartPre =
          let
            args = lib.escapeShellArgs [
              "--db-file"
              "/var/lib/beegfs-mgmtd/mgmtd.sqlite"
              "--log-target"
              "stderr"
            ];
          in
          "${pkgs.writeShellScript "beegfs-mgmtd-init" ''
            if [ ! -e /var/lib/beegfs-mgmtd/mgmtd.sqlite ]; then
              exec ${cfg.mgmtd.package}/bin/beegfs-mgmtd --init ${args}
            fi
          ''}";
        ExecStart = lib.escapeShellArgs ([
          "${cfg.mgmtd.package}/bin/beegfs-mgmtd"
          "--config-file"
          mgmtdConfFile
          "--db-file"
          "/var/lib/beegfs-mgmtd/mgmtd.sqlite"
          "--log-target"
          "journald"
          "--beemsg-port"
          (toString cfg.mgmtd.port)
          "--grpc-port"
          (toString cfg.mgmtd.grpcPort)
        ]
        ++ (if cfg.authDisable then
          [ "--auth-disable" ]
        else
          [ "--auth-file" "%d/conn.auth" ])
        ++ (if cfg.mgmtd.tls.certFile != null then [
          "--tls-cert-file"
          "%d/cert.pem"
          "--tls-key-file"
          "%d/key.pem"
        ] else
          [ "--tls-disable" ])
        ++ cfg.mgmtd.extraArgs);
      };
    });

    ## Metadata daemon ######################################################

    systemd.services.beegfs-meta = lib.mkIf cfg.meta.enable (daemonCommon // {
      description = "BeeGFS metadata daemon";
      unitConfig.RequiresMountsFor = [ cfg.meta.directory ];
      serviceConfig = commonHardening // {
        # Root, not a service user: node registration reads the root-only
        # /sys/class/dmi/id/product_uuid for the machine UUID, and metadata
        # files carry arbitrary client uid/gid (chown).
        LoadCredential = authCredential;
        ReadWritePaths = [ cfg.meta.directory ];
        LimitNOFILE = 262144;
        Restart = "on-failure";
        RestartSec = "5s";
        ExecStart = "${cfg.package}/bin/beegfs-meta cfgFile=${metaConf}";
      };
    });

    ## Storage daemon #######################################################

    systemd.services.beegfs-storage = lib.mkIf cfg.storage.enable (daemonCommon // {
      description = "BeeGFS storage daemon";
      unitConfig.RequiresMountsFor = cfg.storage.directories;
      serviceConfig = commonHardening // {
        # Root for the same reasons as beegfs-meta (machine UUID, chunk
        # file ownership for quota accounting).
        LoadCredential = authCredential;
        ReadWritePaths = cfg.storage.directories;
        LimitNOFILE = 262144;
        Restart = "on-failure";
        RestartSec = "5s";
        ExecStart = "${cfg.package}/bin/beegfs-storage cfgFile=${storageConf}";
      };
    });

    systemd.tmpfiles.rules =
      lib.optional cfg.meta.enable
        "d ${cfg.meta.directory} 0700 root root -"
      ++ lib.optionals cfg.storage.enable
        (map (d: "d ${d} 0700 root root -") cfg.storage.directories);

    ## Client ###############################################################

    boot.extraModulePackages =
      lib.mkIf cfg.client.enable [ cfg.client.modulePackage ];
    boot.kernelModules = lib.mkIf cfg.client.enable [ "beegfs" ];

    # Explicit mount units rather than fileSystems: precise network deps,
    # and fileSystems is wholesale-overridden (mkVMOverride) inside NixOS
    # VM tests, which would silently drop the mounts there.
    systemd.mounts = lib.mkIf cfg.client.enable (lib.mapAttrsToList
      (mountPoint: mount: {
        what = "beegfs_nodev";
        where = mountPoint;
        type = "beegfs";
        # _netdev makes systemd apply remote-fs ordering. Without it, the
        # out-of-tree filesystem type is mistaken for a local mount and its
        # network-online dependency can create a local-fs boot cycle.
        options = "_netdev,cfgFile=${clientConf {
          name = lib.strings.sanitizeDerivationName mountPoint;
          inherit (mount) settings;
        }}";
        after = [ "network-online.target" "systemd-modules-load.service" ];
        wants = [ "network-online.target" ];
        wantedBy = lib.optional (!mount.automount) "remote-fs.target";
        mountConfig.TimeoutSec = mount.mountTimeoutSec;
      })
      cfg.client.mounts);

    # An automount unit is safe to start without a live BeeGFS cluster: it
    # only installs the kernel trigger. The matching mount unit remains
    # bounded by mountTimeoutSec and runs on first access.
    systemd.automounts = lib.mkIf cfg.client.enable (lib.mapAttrsToList
      (mountPoint: mount: {
        where = mountPoint;
        wantedBy = [ "remote-fs.target" ];
        automountConfig.TimeoutIdleSec = mount.idleTimeoutSec;
      })
      (lib.filterAttrs (_: mount: mount.automount) cfg.client.mounts));

    ## Firewall #############################################################

    networking.firewall = {
      allowedTCPPorts =
        lib.optionals (cfg.mgmtd.enable && cfg.mgmtd.openFirewall) [
          cfg.mgmtd.port
          cfg.mgmtd.grpcPort
        ]
        ++ lib.optional (cfg.meta.enable && cfg.meta.openFirewall) cfg.meta.port
        ++ lib.optional (cfg.storage.enable && cfg.storage.openFirewall) cfg.storage.port;
      allowedUDPPorts =
        lib.optional (cfg.mgmtd.enable && cfg.mgmtd.openFirewall) cfg.mgmtd.port
        ++ lib.optional (cfg.meta.enable && cfg.meta.openFirewall) cfg.meta.port
        ++ lib.optional (cfg.storage.enable && cfg.storage.openFirewall) cfg.storage.port;
    };
  };
}
