{ config, lib, pkgs, ... }:

with lib;
let

  cfg = config.services.akula;
in
{

  options = {
    services.akula = {

      enable = lib.mkEnableOption (lib.mdDoc "Akula Ethereum node");

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/akula";
        description = lib.mdDoc ''
          Directory where data will be stored. Each chain will be stored under it's own specific subdirectory.
        '';
      };

      chain = mkOption {
        type = types.str;
        default = "mainnet";
        description = lib.mdDoc ''
          Name of the network to join
        '';
      };

      address = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = lib.mdDoc ''
          Listen address of node.
        '';
      };

      port = mkOption {
        type = types.port;
        default = 30303;
        description = lib.mdDoc ''
          Port number the node will be listening on.
        '';
      };

      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Open the port in the firewall
        '';
      };

      jwtPath = mkOption {
        type = types.str;
        default = "";
        description = lib.mdDoc ''
          Path for the jwt secret required to connect to the execution layer.
        '';
      };

      http = {
        enable = lib.mkEnableOption (lib.mdDoc "Beacon node http api");
        port = mkOption {
          type = types.port;
          default = 5052;
          description = lib.mdDoc ''
            Port number of Beacon node RPC service.
          '';
        };

        address = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = lib.mdDoc ''
            Listen address of Beacon node RPC service.
          '';
        };
      };

      metrics = {
        enable = lib.mkEnableOption (lib.mdDoc "Beacon node prometheus metrics");
        address = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = lib.mdDoc ''
            Listen address of Beacon node metrics service.
          '';
        };

        port = mkOption {
          type = types.port;
          default = 5054;
          description = lib.mdDoc ''
            Port number of Beacon node metrics service.
          '';
        };
      };

      extraArgs = mkOption {
        type = types.str;
        description = lib.mdDoc ''
          Additional arguments passed to the akula beacon command.
        '';
        default = "";
        example = "";
      };
    };
  };

  config = mkIf cfg.enable {

    environment.systemPackages = [ pkgs.akula ];

    networking.firewall = mkIf cfg.enable {
      allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
      allowedUDPPorts = mkIf cfg.openFirewall [ cfg.port ];
    };

    systemd.services.akula = mkIf cfg.enable {
      description = "akula node (connect to P2P nodes and verify blocks)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      script = ''
        # make sure the chain data directory is created on first run
        mkdir -p ${cfg.dataDir}/${cfg.chain}

        ${pkgs.akula}/bin/akula \
          --listen-port ${toString cfg.port} \
          --listen-addr ${cfg.address} \
          --chain ${cfg.chain} \
          --datadir ${cfg.dataDir}/${cfg.chain} \
          --jwt-secret-path ''${CREDENTIALS_DIRECTORY}/AKULA_JWT \
        ${lib.optionalString cfg.http.enable '' --http --http-address ${cfg.http.address} --http-port ${toString cfg.beacon.http.port}''} \
        ${lib.optionalString cfg.metrics.enable '' --metrics --metrics-address ${cfg.metrics.address} --metrics-port ${toString cfg.beacon.metrics.port}''} \
        ${cfg.extraArgs}
      '';
      serviceConfig = {
        LoadCredential = "AKULA_JWT:${cfg.jwtPath}";
        DynamicUser = true;
        Restart = "on-failure";
        StateDirectory = "akula";
        ReadWritePaths = [ cfg.dataDir ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectClock = true;
        ProtectProc = "noaccess";
        ProcSubset = "pid";
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        RestrictSUIDSGID = true;
        RestrictRealtime = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        RemoveIPC = true;
        SystemCallFilter = [ "@system-service" "~@privileged" ];
      };
    };
  };
}
