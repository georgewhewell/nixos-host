{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.geth-local;
  cmdArgs =
    [
      "--http"
      "--http.addr" "0.0.0.0"
      "--http.port" cfg.apiPort
      "--http.vhosts" "nixhost.lan,127.0.0.1,localhost"
      "--ws"
      "--ws.addr" "0.0.0.0"
      "--ws.port" cfg.wsPort
      "--cache" cfg.cacheSize
      "--light.maxpeers" "1"
      "--light.egress" "10"
      "--maxpeers" "4"
    ];
in
{
  options = {
    services.geth-local = {
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

      cacheSize = mkOption {
        type = types.int;
        default = 1024;
        description = ''
          --cache=
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

    networking.firewall.allowedTCPPorts = [ cfg.apiPort cfg.wsPort 30303 ];
    networking.firewall.allowedUDPPorts = [ 30303 ];

    users.users.geth = {
      group = cfg.group;
      description = "geth user";
      home = "/var/lib/geth/";
      extraGroups = [ "docker" ];
      isNormalUser = true;
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
