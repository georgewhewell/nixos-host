{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.services.p2pool-exporter;
in {
  options = {
    services.p2pool-exporter = {
      enable = lib.mkEnableOption "P2Pool Prometheus exporter";

      p2poolApiUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:3333";
        description = ''
          URL of the P2Pool API endpoint.
        '';
      };

      walletAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["4878JKf387qCg1dT6Gs1wERmosrTqxtUR185xeMXpTW3f9TRkM6vD5dHABzULx5DTDZFC9XcdQ1nW3ZksvNp34pVBmNCEfm"];
        description = ''
          List of Monero wallet addresses to monitor.
        '';
      };

      scrapeInterval = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          Time between data scrapes in seconds. If null, uses the exporter's default.
        '';
      };

      logLevel = lib.mkOption {
        type = lib.types.enum ["DEBUG" "INFO" "WARNING" "ERROR"];
        default = "INFO";
        description = ''
          Log level for the exporter.
        '';
      };

      exchangeRates = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["EUR" "USD"];
        description = ''
          Exchange rates to track.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable Redis for p2pool-exporter
    services.redis.servers.p2pool.enable = true;

    users.users.p2pool-exporter = {
      isSystemUser = true;
      group = "p2pool-exporter";
      description = "P2Pool exporter user";
    };

    users.groups.p2pool-exporter = {};

    systemd.services.p2pool-exporter = {
      description = "P2Pool Prometheus exporter";
      after = ["network.target" "p2pool.service" "redis-p2pool.service"];
      wantedBy = ["multi-user.target"];

      environment = {
        OTEL_SERVER = "127.0.0.1:4318";
        REDIS_SERVER = "127.0.0.1:6379";
      };

      serviceConfig = {
        Type = "simple";
        User = "p2pool-exporter";
        Group = "p2pool-exporter";
        Restart = "always";
        RestartSec = 10;

        ExecStart = ''
          ${inputs.p2pool-exporter.packages.${pkgs.stdenv.hostPlatform.system}.p2pool-exporter}/bin/p2pool-exporter \
            -a ${cfg.p2poolApiUrl} \
            -w ${lib.concatStringsSep " " cfg.walletAddresses} \
            -l ${cfg.logLevel} \
            ${lib.optionalString (cfg.scrapeInterval != null) "-t ${toString cfg.scrapeInterval}"} \
            -e ${lib.concatStringsSep " " cfg.exchangeRates}
        '';

        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };

  meta.maintainers = with lib.maintainers; [];
}
