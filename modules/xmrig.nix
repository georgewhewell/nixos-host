{
  config,
  pkgs,
  inputs,
  lib,
  network,
  ...
}: let
  common = import ../lib/xmrig.nix { inherit lib network; };
  cfg = config.sconfig.xmrig;
in {
  options.sconfig.xmrig = {
    enable = lib.mkEnableOption "Run XMRig miner";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.xmrig;
      description = "The XMRig package to use for mining.";
    };

    cudaPlugin = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "The CUDA plugin for XMRig, if applicable.";
    };

    walletAddress = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "48...your_monero_primary_or_subaddress";
      description = "Monero wallet address used for payouts (XMRig user field).";
    };

    poolHost = lib.mkOption {
      type = lib.types.str;
      default = (network.primaryIp network.hosts.trex);
      description = "P2Pool stratum host to connect to.";
    };

    poolPort = lib.mkOption {
      type = lib.types.port;
      default = 3333;
      description = "P2Pool stratum port to connect to.";
    };

    uclampMax = lib.mkOption {
      type = lib.types.nullOr (lib.types.ints.between 0 100);
      default = null;
      example = 50;
      description = "CPU utilization clamp maximum (0-100%).";
    };

    httpApi = {
      enable = lib.mkEnableOption "XMRig HTTP API";

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Host/address for the XMRig HTTP API listener.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8082;
        description = "Port for the XMRig HTTP API.";
      };

      restricted = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether the XMRig HTTP API runs in restricted (read-only) mode.";
      };

      accessToken = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Access token for the HTTP API.
          If null, a deterministic per-host local token is used.
        '';
      };
    };

    mqttSwitch = common.mqttSwitchOptions;

    inhibit = {
      nixDaemonBuilds = {
        enable = lib.mkEnableOption "Pause xmrig mining when nix-daemon is actively building";

        quietSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 120;
          description = "How long to wait after the last nix-daemon build log event before resuming.";
        };
      };

      dota2 = {
        enable = lib.mkEnableOption "Pause xmrig mining when Dota 2 activity is seen in journald";

        quietSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 600;
          description = "How long to keep xmrig inhibited after the last Dota 2 journal match.";
        };

        patterns = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "\\bdota2\\b"
            "\\bdota\\b"
            "appid\\s*570"
          ];
          description = "Case-insensitive Python regex patterns to detect Dota 2 activity.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable (let
    mqttCfg = cfg.mqttSwitch;
    nixDaemonInhibitCfg = cfg.inhibit.nixDaemonBuilds;
    dota2InhibitCfg = cfg.inhibit.dota2;
    hostName = config.networking.hostName;
    xmrigApiToken =
      if cfg.httpApi.accessToken != null
      then cfg.httpApi.accessToken
      else "xmrig-${hostName}-local";

    topics = common.mkMqttTopics { inherit mqttCfg hostName; };
    payloads = common.mkDiscoveryPayloads {
      inherit hostName topics;
      platformModel = "Linux Host";
    };
    mqttAgentConfig = common.mkMqttAgentConfig { inherit mqttCfg topics payloads; };

    agentConfigJson = builtins.toJSON {
      platform = "linux";
      mqtt = mqttAgentConfig;
      xmrigApi = {
        baseUrl = "http://${cfg.httpApi.host}:${toString cfg.httpApi.port}";
        token = xmrigApiToken;
      };
      inhibitor = {
        nixBuilds = {
          enable = nixDaemonInhibitCfg.enable;
          quietSeconds = nixDaemonInhibitCfg.quietSeconds;
        };
        dota2 = {
          enable = dota2InhibitCfg.enable;
          quietSeconds = dota2InhibitCfg.quietSeconds;
          patterns = dota2InhibitCfg.patterns;
        };
      };
      system = {
        systemctl = "${pkgs.systemd}/bin/systemctl";
        journalctl = "${pkgs.systemd}/bin/journalctl";
        stateDir = "/var/lib/xmrig-mqtt";
      };
    };

    xmrigMqttAgentPython = common.mkMqttAgentPython { inherit pkgs agentConfigJson; };

    # Shell script for ExecStopPost — publish offline availability on service stop
    xmrigPublishAvailabilityScript = pkgs.writeShellScript "xmrig-mqtt-publish-availability" ''
      set -euo pipefail
      payload="''${1:-}"
      case "$payload" in
        online|offline) ;;
        *)
          echo "usage: $0 {online|offline}" >&2
          exit 2
          ;;
      esac
      pw_file=${lib.escapeShellArg (toString mqttCfg.passwordFile)}
      if [ ! -r "$pw_file" ]; then
        exit 1
      fi
      pw="$(${pkgs.coreutils}/bin/cat "$pw_file")"
      ${pkgs.mosquitto}/bin/mosquitto_pub \
        -h ${lib.escapeShellArg mqttCfg.host} \
        -p ${lib.escapeShellArg (toString mqttCfg.port)} \
        -u ${lib.escapeShellArg mqttCfg.username} \
        -P "$pw" \
        -q ${toString mqttCfg.qos} \
        -r \
        -t ${lib.escapeShellArg topics.availabilityTopic} \
        -m "$payload"
    '';
  in {
    sconfig.xmrig.httpApi.enable = lib.mkDefault mqttCfg.enable;
    sconfig.xmrig.mqttSwitch.enable = lib.mkDefault (mqttCfg.passwordFile != null);
    sconfig.xmrig.mqttSwitch.passwordFile = lib.mkDefault (
      lib.attrByPath ["sops" "secrets" "mosquitto-password" "path"] null config
    );
    sconfig.xmrig.inhibit.nixDaemonBuilds.enable = lib.mkDefault mqttCfg.enable;

    environment.persistence = lib.mkIf (config.sconfig.impermanence.enable && mqttCfg.enable) {
      ${config.sconfig.impermanence.persistentStoragePath}.directories = [
        "/var/lib/xmrig-mqtt"
      ];
    };

    assertions = [
      {
        assertion = (!mqttCfg.enable) || (mqttCfg.username != null && mqttCfg.passwordFile != null);
        message = "sconfig.xmrig.mqttSwitch requires `username` and `passwordFile` when enabled";
      }
    ];

    environment.systemPackages = [cfg.package];
    systemd.services.xmrig = {
      environment = lib.mkIf (cfg.cudaPlugin != null) {
        LD_LIBRARY_PATH = "/run/opengl-driver/lib";
      };
      serviceConfig = {
        Nice = 19;
        CPUWeight = 1;
        IOWeight = 1;
        Restart = "always";
        RestartSec = "30s";
        RuntimeMaxSec = "12h";
      };
      postStart =
        lib.optionalString (cfg.uclampMax != null) ''
          echo "${toString cfg.uclampMax}.00" > /sys/fs/cgroup/system.slice/xmrig.service/cpu.uclamp.max
        '';
    };

    systemd.services.xmrig-mqtt = lib.mkIf mqttCfg.enable {
      description = "MQTT control/discovery agent for xmrig";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "sops-install-secrets.service"];
      wants = ["network-online.target" "sops-install-secrets.service"];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "2s";
        StateDirectory = "xmrig-mqtt";
        ExecStart = "${xmrigMqttAgentPython}/bin/xmrig-mqtt-agent";
        ExecStopPost = [ "-${xmrigPublishAvailabilityScript} offline" ];
      };
      path = [pkgs.mosquitto pkgs.coreutils pkgs.systemd pkgs.curl pkgs.gnugrep];
    };

    services.xmrig = {
      enable = true;
      package = cfg.package;
      settings = {
        cpu = {
          enabled = true;
          priority = 1;
          max-threads-hint = 99;
        };
        randomx = {
          "1gb-pages" = true;
        };
        opencl = false;
        cuda =
          if cfg.cudaPlugin != null
          then {
            enabled = true;
            loader = "${cfg.cudaPlugin}/libxmrig-cuda.so";
          }
          else false;
        pools = [
          {
            url = "${cfg.poolHost}:${toString cfg.poolPort}";
            user = config.networking.hostName;
            pass = config.networking.hostName;
          }
        ];
      }
      // lib.optionalAttrs cfg.httpApi.enable {
        http = {
          enabled = true;
          host = cfg.httpApi.host;
          port = cfg.httpApi.port;
          restricted = cfg.httpApi.restricted;
          "access-token" = xmrigApiToken;
        };
      };
    };

    # Configure mtail to monitor xmrig logs from journald
    services.mtail = {
      enable = true;
      openFirewall = true;
      journaldUnits = ["xmrig"];
      programs.xmrig = ''
        # XMRig miner metrics parser
        # Extracts hashrate, accepted/rejected shares, and difficulty

        # Gauges for current hashrate (updated every 60s)
        gauge xmrig_hashrate_10s
        gauge xmrig_hashrate_60s
        gauge xmrig_hashrate_15m
        gauge xmrig_hashrate_max

        # Counters for shares
        counter xmrig_shares_accepted_total
        counter xmrig_shares_rejected_total

        # Gauge for current difficulty
        gauge xmrig_difficulty_current

        # Histogram for share response time
        histogram xmrig_share_response_time_ms buckets 0, 1, 5, 10, 50, 100, 500, 1000

        # Parse miner speed line:
        # [2025-11-12 23:27:26.500]  miner    speed 10s/60s/15m 43992.8 44216.1 44746.0 H/s max 45885.5 H/s
        /\[.+\]\s+miner\s+speed\s+10s\/60s\/15m\s+(?P<speed_10s>[\d\.]+)\s+(?P<speed_60s>[\d\.]+)\s+(?P<speed_15m>[\d\.]+|n\/a)\s+H\/s\s+max\s+(?P<speed_max>[\d\.]+)\s+H\/s/ {
          xmrig_hashrate_10s = float($speed_10s)
          xmrig_hashrate_60s = float($speed_60s)

          # Handle n/a for 15m average (when just started)
          $speed_15m != "n/a" {
            xmrig_hashrate_15m = float($speed_15m)
          }

          xmrig_hashrate_max = float($speed_max)
        }

        # Parse accepted shares:
        # [2025-11-12 23:27:34.309]  cpu      accepted (50/0) diff 1552K (1 ms)
        /\[.+\]\s+cpu\s+accepted\s+\((?P<accepted>\d+)\/(?P<rejected>\d+)\)\s+diff\s+(?P<diff>[\d\.]+)K\s+\((?P<response_ms>\d+)\s+ms\)/ {
          xmrig_shares_accepted_total = int($accepted)
          xmrig_shares_rejected_total = int($rejected)
          xmrig_difficulty_current = float($diff)
          xmrig_share_response_time_ms = int($response_ms)
        }

        # Parse rejected shares (if they occur):
        # [timestamp]  cpu      rejected (accepted/rejected) diff XK (Y ms) "reason"
        /\[.+\]\s+cpu\s+rejected\s+\((?P<accepted>\d+)\/(?P<rejected>\d+)\)\s+diff\s+(?P<diff>[\d\.]+)K/ {
          xmrig_shares_accepted_total = int($accepted)
          xmrig_shares_rejected_total = int($rejected)
          xmrig_difficulty_current = float($diff)
        }
      '';
    };
  });
}
