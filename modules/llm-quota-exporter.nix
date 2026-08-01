{ pkgs, config, lib, ... }:

let
  cfg = config.services.llm-quota-exporter;
in
{
  options.services.llm-quota-exporter = {
    enable = lib.mkEnableOption "Prometheus exporter for LLM subscription quotas";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9184;
      description = "Port to expose the metrics endpoint on";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address to bind the metrics endpoint to";
    };

    interval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = "Seconds between polls of the upstream quota endpoints";
    };

    providers = lib.mkOption {
      type = lib.types.str;
      default = "all";
      example = "anthropic,openai";
      description = "Comma-separated provider subset, or \"all\"";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "grw";
      description = "User whose home directory holds the CLI credential files; the service runs as this user";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the metrics port in the firewall";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.llm-quota-exporter = {
      description = "LLM subscription quota Prometheus exporter";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = lib.escapeShellArgs [
          (lib.getExe pkgs.llm-quota-exporter)
          "--listen-address" cfg.listenAddress
          "--port" (toString cfg.port)
          "--interval" (toString cfg.interval)
          "--providers" cfg.providers
          "--home" config.users.users.${cfg.user}.home
        ];
        User = cfg.user;
        Group = config.users.users.${cfg.user}.group;
        Restart = "on-failure";
        RestartSec = "30s";
        # Home is read-only except the credential stores of the providers that
        # rotate refresh tokens (grok, kimi) — those must persist rotated pairs.
        ProtectHome = "read-only";
        ReadWritePaths = let home = config.users.users.${cfg.user}.home; in [
          "-${home}/.grok"
          "-${home}/.kimi-code/credentials"
          "-${home}/.kimi/credentials"
        ];
        ProtectSystem = "strict";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
