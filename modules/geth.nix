{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.geth;
  cmdArgs =
    [
      "--syncmode" "fast"
      "--http"
      "--http.port" cfg.apiPort
      "--http.addr" "0.0.0.0"
      "--http.vhosts" "nixhost.lan"
      "--ws"
      "--ws.port" cfg.wsPort
      "--ws.addr" "0.0.0.0"
    ];
in
{
  options = {
    services.geth = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "If enabled, start the geth server.";
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
        default = "geth";
        description = ''
          User to use when running geth.
        '';
      };

      group = mkOption {
        type = types.str;
        default = "geth";
        description = ''
          Group to use when running geth.
        '';
      };
    };
  };

  config = mkIf cfg.enable {

    networking.firewall.allowedTCPPorts = [ cfg.apiPort cfg.wsPort ];

    users.users.geth = {
      group = cfg.group;
      description = "geth user";
      home = "/var/lib/geth/";
      createHome = true;
    };

    users.groups.geth = {
      name = "geth";
    };

    systemd.services.geth = {
      description = "geth Service";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "network-online.target "];

      serviceConfig = {
        ExecStart = "${pkgs.go-ethereum}/bin/geth ${escapeShellArgs cmdArgs}";
        User = cfg.user;
        Group = cfg.group;
      };
    };
  };
}
