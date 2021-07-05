{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.graph-node;
  cmdArgs =
    [
        "--ethereum-rpc" cfg.ethereumRpc
        "--postgres-url" cfg.postgresUrl
        "--ipfs" cfg.ipfs
    ];
in
{
  options = {
    services.graph-node = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "If enabled, start the graph-node server.";
      };

      ethereumRpc = mkOption {
        type = types.str;
        default = "mainnet:http://localhost:8545";
        description = ''
          ethereum-rpc address
        '';
      };

      postgresUrl = mkOption {
        type = types.str;
        # default = "mainnet:http://localhost:8545";
        description = ''
          ethereum-rpc address
        '';
      };

      ipfs = mkOption {
        type = types.str;
        # default = "mainnet:http://localhost:8545";
        description = ''
          ethereum-rpc address
        '';
      };
    #   apiPort = mkOption {
    #     type = types.int;
    #     default = 8545;
    #     description = ''
    #       api port
    #     '';
    #   };

    #   wsPort = mkOption {
    #     type = types.int;
    #     default = 8546;
    #     description = ''
    #       api port
    #     '';
    #   };

    #   unsafeExpose = mkOption {
    #     type = types.bool;
    #     default = false;
    #     description = ''
    #       unsafe
    #     '';
    #   };

    #   noAncientBlocks = mkOption {
    #     type = types.bool;
    #     default = true;
    #     description = ''
    #       no ancient blocks
    #     '';
    #   };

      user = mkOption {
        type = types.str;
        default = "graph-node";
        description = ''
          User to use when running graph-node
        '';
      };

      group = mkOption {
        type = types.str;
        default = "graph-node";
        description = ''
          Group to use when running graph-node
        '';
      };
    };
  };

  config = mkIf cfg.enable {

    # networking.firewall.allowedTCPPorts = [ cfg.apiPort cfg.wsPort ];

    users.users.graph-node = {
      group = cfg.group;
      description = "graph-node user";
      home = "/var/lib/graph-node/";
      createHome = true;
    };

    users.groups.graph-node = {
      name = "graph-node";
    };

    systemd.services.graph-node = {
      description = "graph-node Service";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "network-online.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.graph-node}/bin/graph-node ${escapeShellArgs cmdArgs}";
        User = cfg.user;
        Group = cfg.group;
      };
    };
  };
}
