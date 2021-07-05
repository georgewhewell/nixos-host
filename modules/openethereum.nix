{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.openethereum;

  cmdArgs =
    [
      "--jsonrpc-port" cfg.apiPort
      "--ws-port" cfg.wsPort
    ]
    ++ optionals cfg.noAncientBlocks [ "--no-ancient-blocks" ]
    ++ optionals cfg.unsafeExpose [ "--unsafe-expose" ];
in
{
  options = {
    services.openethereum = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "If enabled, start the openethereum server.";
      };

      apiPort = mkOption {
        type = types.int;
        default = 8545;
        description = ''
          api port
        '';
      };

      wsPort = mkOption {
        type = types.int;
        default = 8546;
        description = ''
          api port
        '';
      };

      unsafeExpose = mkOption {
        type = types.bool;
        default = false;
        description = ''
          unsafe
        '';
      };

      noAncientBlocks = mkOption {
        type = types.bool;
        default = true;
        description = ''
          no ancient blocks
        '';
      };

      user = mkOption {
        type = types.str;
        default = "openethereum";
        description = ''
          User to use when running openethereum.
        '';
      };

      group = mkOption {
        type = types.str;
        default = "openethereum";
        description = ''
          Group to use when running openethereum.
        '';
      };
    };
  };

  config = mkIf cfg.enable {

    networking.firewall.allowedTCPPorts = [ cfg.apiPort cfg.wsPort ];

    users.users.openethereum = {
      group = cfg.group;
      description = "openethereum user";
      home = "/var/lib/openethereum/";
      createHome = true;
    };

    users.groups.openethereum = {
      name = "openethereum";
    };

    systemd.services.openethereum = {
      description = "openethereum Service";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "network-online.target "];

      serviceConfig = {
        ExecStart = "${pkgs.openethereum}/bin/openethereum ${escapeShellArgs cmdArgs}";
        User = cfg.user;
        Group = cfg.group;
      };
    };
  };
}
