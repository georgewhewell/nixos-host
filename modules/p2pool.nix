{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.p2pool;
in {
  # The fleet module also supplies merge-mining and mtail integration.
  # Newer nixpkgs ships the same option namespace; keep one provider.
  disabledModules = [ "services/networking/p2pool.nix" ];

  options = {
    services.p2pool = {
      enable = lib.mkEnableOption "Monero P2Pool node daemon";

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/p2pool";
        description = ''
          The directory where p2pool stores its data files.
        '';
      };

      mini =
        lib.mkEnableOption ""
        // {
          description = "Whether to mine on P2Pool Mini (true) or Main (false).";
        };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          The IP address of your Monero node.
        '';
      };

      logLevel = lib.mkOption {
        type = lib.types.ints.between 0 6;
        default = 2;
        description = ''
          Log level for the P2Pool node. (Between 0 - 6)
        '';
      };

      rpcPort = lib.mkOption {
        type = lib.types.port;
        default = 18081;
        description = ''
          Monero daemon RPC API port.
        '';
      };

      zmqPort = lib.mkOption {
        type = lib.types.port;
        default = 18083;
        description = ''
          Monero daemon ZMQ pub port.
        '';
      };

      stratumPort = lib.mkOption {
        type = lib.types.port;
        default = 3333;
        description = ''
          Port for stratum server to listen on.
        '';
      };

      p2pPort = lib.mkOption {
        type = lib.types.port;
        default = 37889;
        description = ''
          Port for P2Pool P2P server to listen on.
        '';
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to open firewall ports for P2Pool.
        '';
      };

      mergeMining = {
        enable = lib.mkEnableOption "Tari merge mining";

        tariHost = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "IP address of the Tari base node gRPC for merge mining.";
        };

        tariPort = lib.mkOption {
          type = lib.types.port;
          default = 18142;
          description = "Tari base node gRPC port (used for merge mining).";
        };

        tariWalletAddress = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Tari wallet address for merge mining payouts.
            Can use environment variable substitution (e.g. "$TARI_WALLET_ADDRESS")
            when used with environmentFile.
          '';
        };
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          Extra command-line arguments to pass to p2pool.
        '';
      };

      socks5.enable = lib.mkEnableOption "connecting to a SOCKS5 proxy for outgoing connections";

      socks5.ip = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          IP address of the SOCKS5 proxy to connect to.
        '';
      };

      socks5.port = lib.mkOption {
        type = lib.types.port;
        default = 9050;
        description = ''
          The port number of the SOCKS5 proxy.
        '';
      };

      walletAddress = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          The Monero wallet address used for mining payouts.
        '';
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/var/lib/p2pool/p2pool.env";
        description = ''
          Path to an EnvironmentFile for the p2pool service as defined in {manpage}`systemd.exec(5)`.

          Secrets may be passed to the service by specifying placeholder variables in the Nix config
          and setting values in the environment file.

          Example:

          ```
          # In environment file:
          WALLET_ADDRESS=888tNkZrPN6JsEgekjMnABU4TBzc2Dt29EPAvkRxbANsAnjyPbb3iQ1YBRk1UXcdRsiKc9dhwMVgN5S9cQUiyoogDavup3H
          ```

          ```
          # Service config
          services.p2pool.walletAddress = "$WALLET_ADDRESS";
          ```
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.p2pool = {
      isSystemUser = true;
      group = "p2pool";
      description = "P2Pool node user";
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.p2pool = {};

    systemd.services.p2pool = {
      description = "P2Pool node";
      after = [
        "network.target"
        "system-modules-load.target"
      ];
      wants = [
        "network.target"
        "system-modules-load.target"
      ];
      wantedBy = ["multi-user.target"];
      script = ''
        ${lib.getExe pkgs.p2pool} \
          --data-dir ${cfg.dataDir} \
          --rpc-port ${toString cfg.rpcPort} \
          --zmq-port ${toString cfg.zmqPort} \
          --host ${cfg.host} \
          --stratum 0.0.0.0:${toString cfg.stratumPort} \
          --p2p 0.0.0.0:${toString cfg.p2pPort} \
          --no-stratum-http \
          --loglevel ${toString cfg.logLevel}${lib.optionalString cfg.mini " \\\n  --mini"}${lib.optionalString cfg.socks5.enable " \\\n  --socks5 ${cfg.socks5.ip}:${toString cfg.socks5.port}"}${lib.optionalString (cfg.walletAddress != "") " \\\n  --wallet ${cfg.walletAddress}"}${lib.optionalString cfg.mergeMining.enable " \\\n  --merge-mine tari://${cfg.mergeMining.tariHost}:${toString cfg.mergeMining.tariPort} ${cfg.mergeMining.tariWalletAddress}"}${lib.optionalString (cfg.extraArgs != []) " \\\n  ${lib.escapeShellArgs cfg.extraArgs}"}
      '';

      serviceConfig = {
        Type = "simple";
        User = "p2pool";
        Group = "p2pool";
        Restart = "always";
        RestartSec = 10;
        WorkingDirectory = cfg.dataDir;
        LimitNOFILE = 65536;
        StandardInput = "null";
        StandardOutput = "journal";
        StandardError = "journal";

        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) [cfg.environmentFile];
      };
    };

    assertions = [
      {
        assertion = cfg.walletAddress != "";
        message = "A wallet address must be specified.";
      }
      {
        assertion = cfg.mergeMining.enable -> cfg.mergeMining.tariWalletAddress != null;
        message = "A Tari wallet address must be specified when merge mining is enabled.";
      }
    ];

    # Configure mtail to monitor p2pool logs from journald
    services.mtail = {
      enable = true;
      openFirewall = true;
      journaldUnits = ["p2pool"];
      programs.p2pool = ''
        # P2Pool metrics parser
        counter p2pool_share_found_total by user
        gauge p2pool_share_difficulty by user
        gauge p2pool_share_effort by user
        counter p2pool_block_found_total
        counter p2pool_payout_total
        counter p2pool_payout_xmr_total
        counter p2pool_payout_missed_total

        # Share found - filter restart noise (diff < 10000000)
        # Real shares have diff in the billions; restart replays ramp from 100000 to ~4M
        /StratumServer SHARE FOUND: mainchain height \d+, sidechain height \d+, diff (?P<diff>\d+), client [^,]+, user (?P<user>\w+), effort (?P<effort>[\d\.]+)%/ {
          int($diff) > 10000000 {
            p2pool_share_found_total[$user]++
            p2pool_share_difficulty[$user] = int($diff)
            p2pool_share_effort[$user] = float($effort)
          }
        }

        # Pool found a block
        /P2Pool BLOCK FOUND: main chain block at height/ {
          p2pool_block_found_total++
        }

        # Payout received
        /got a payout of (?P<amount>[\d\.]+) XMR in block/ {
          p2pool_payout_total++
          p2pool_payout_xmr_total += float($amount)
        }

        # Missed payout
        /didn't get a payout in block/ {
          p2pool_payout_missed_total++
        }
      '';
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [
        cfg.stratumPort
        cfg.p2pPort
      ];
      allowedUDPPorts = [
        cfg.p2pPort
      ];
    };
  };

  meta.maintainers = with lib.maintainers; [JacoMalan1];
}
