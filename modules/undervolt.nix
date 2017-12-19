{config, lib, pkgs, ...}:

with lib;

let
  cfg = config.services.bitcoin;
in
  {
    options.hardware.undervolt = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          When enabled, automatically apply undervolts on boot and after resume
        '';
      };

      cpu = mkOption {
        type = types.integer;
        default = null;
        description = ''
          CPU Core (0)
        '';
      };

      gpu = mkOption {
        type = types.integer;
        default = null;
        description = ''
          Intel GPU (1)
        '';
      };

      0 - CPU Core

1 - Intel GPU

2 - CPU Cache

      cache = mkOption {
        type = types.integer;
        default = null;
        description = ''
          CPU Cache (2)
        '';
      };
3 - System Agent

      agent = mkOption {
        type = types.integer;
        default = null;
        description = ''
          System Agent (3)
        '';
      };
4 - Analog I/O

      aio = mkOption {
        type = types.integer;
        default = null;
        description = ''
          Analog I/O
        '';
      };

      dio = mkOption {
        type = types.integer;
        default = null;
        description = ''
          Digital I/O
        '';
      };
    };

    config = mkIf cfg.enable {
      environment.systemPackages = [cfg.package];

      users.users.bitcoin = {
        createHome = false;
        description = "Bitcoin Client";
        home = cfg.dataDir;
        isSystemUser = true;
      };

      systemd.services.bitcoin = {
        description = "Bitcoind Client";
        after = ["network.target" "local-fs.target"];
        wantedBy = ["multi-user.target"];
        preStart = ''
          mkdir -p ${cfg.dataDir}
          chown bitcoin ${cfg.dataDir}
        '';
        script = ''
          ${cfg.package}/bin/bitcoind -datadir=${cfg.dataDir} -server -upnp -whitelist-rpc-ip=127.0.0.1 -alertnotify=echo -blocknotify=echo -rpcuser=moon -rpcpassword=moon -zmqpubrawtx=tcp://127.0.0.1:28332
        '';
        serviceConfig = {
          PermissionsStartOnly = true; # preStart must be run as root
          User = "bitcoin";
          Nice = 10;
        };
      };
    };
    meta = {};
  }
