{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: let
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
      default = "192.168.23.1";
      description = "P2Pool stratum host to connect to.";
    };

    poolPort = lib.mkOption {
      type = lib.types.port;
      default = 3333;
      description = "P2Pool stratum port to connect to.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];
    systemd.services.xmrig = {
      serviceConfig = {
        Nice = 19;
        CPUWeight = 1;
        IOWeight = 1;
        # Restart on failure
        Restart = "always";
        RestartSec = "30s";
        # Restart every 12 hours
        RuntimeMaxSec = "12h";
      };
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
            pass = config.networking.hostName; # rig id / password
          }
        ];
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
  };
}
