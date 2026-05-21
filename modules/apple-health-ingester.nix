{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkOption mkIf types optional escapeShellArg concatStringsSep flatten;
  cfg = config.services.apple-health-ingester;
in {
  options.services.apple-health-ingester = {
    enable = mkEnableOption "Apple Health Ingester service";

    package = mkOption {
      type = types.package;
      default = pkgs.apple-health-ingester;
      defaultText = lib.literalExpression "pkgs.apple-health-ingester";
      description = "The apple-health-ingester package to use";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0:8080";
      description = "Address and port to listen on";
    };

    authTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "File containing the authentication token for the HTTP endpoint";
    };

    logLevel = mkOption {
      type = types.enum ["debug" "info" "warn" "error"];
      default = "info";
      description = "Log level";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/apple-health-ingester";
      description = "Directory for storing data (used by localfile backend)";
    };

    backends = {
      influxdb = {
        enable = mkEnableOption "InfluxDB backend";

        url = mkOption {
          type = types.str;
          default = "http://localhost:8086";
          description = "InfluxDB server URL";
        };

        org = mkOption {
          type = types.str;
          default = "";
          description = "InfluxDB organization";
        };

        bucket = mkOption {
          type = types.str;
          default = "apple_health";
          description = "InfluxDB bucket";
        };

        tokenFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "File containing the InfluxDB authentication token";
        };
      };

      localfile = {
        enable = mkEnableOption "Local file backend";
      };
    };

    extraFlags = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra command line flags to pass to the ingester";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall port for the HTTP listener";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.backends.influxdb.enable || cfg.backends.localfile.enable;
        message = "At least one backend (influxdb or localfile) must be enabled";
      }
    ];

    systemd.services.apple-health-ingester = {
      description = "Apple Health Ingester";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = "apple-health-ingester";
        Group = "apple-health-ingester";
        WorkingDirectory = cfg.dataDir;
        Restart = "on-failure";
        RestartSec = "5s";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        MemoryDenyWriteExecute = true;
        LockPersonality = true;
        ReadWritePaths = [cfg.dataDir];

        LoadCredential =
          optional (cfg.authTokenFile != null) "auth-token:${cfg.authTokenFile}"
          ++ optional (cfg.backends.influxdb.enable && cfg.backends.influxdb.tokenFile != null) "influxdb-token:${cfg.backends.influxdb.tokenFile}";
      };

      script = let
        baseArgs = [
          "--http.listenAddr" (escapeShellArg cfg.listenAddress)
          "--log" cfg.logLevel
        ];
        authArgs = optional (cfg.authTokenFile != null)
          ''--http.authToken "$(cat $CREDENTIALS_DIRECTORY/auth-token)"'';
        influxdbArgs = if cfg.backends.influxdb.enable then [
          "--backend.influxdb"
          "--influxdb.serverURL" (escapeShellArg cfg.backends.influxdb.url)
          "--influxdb.orgName" (escapeShellArg cfg.backends.influxdb.org)
          "--influxdb.metricsBucketName" (escapeShellArg cfg.backends.influxdb.bucket)
        ] ++ optional (cfg.backends.influxdb.tokenFile != null)
          ''--influxdb.authToken "$(cat $CREDENTIALS_DIRECTORY/influxdb-token)"''
        else [];
        localfileArgs = if cfg.backends.localfile.enable then [
          "--backend.localfile"
          "--localfile.metricsPath" (escapeShellArg "${cfg.dataDir}/data")
        ] else [];
        allArgs = flatten (baseArgs ++ authArgs ++ influxdbArgs ++ localfileArgs ++ cfg.extraFlags);
      in ''
        exec ${cfg.package}/bin/ingester ${concatStringsSep " " allArgs}
      '';
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 apple-health-ingester apple-health-ingester -"
      "d ${cfg.dataDir}/data 0750 apple-health-ingester apple-health-ingester -"
    ];

    users.users.apple-health-ingester = {
      isSystemUser = true;
      group = "apple-health-ingester";
      home = cfg.dataDir;
    };

    users.groups.apple-health-ingester = {};

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [
      (lib.toInt (lib.last (lib.splitString ":" cfg.listenAddress)))
    ];
  };
}
