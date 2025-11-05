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
  };
}
