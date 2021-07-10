{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.besu;
  cmdArgs =
    [
      "--metrics-enabled"
      "--rpc-ws-enabled"
      "--rpc-ws-host=0.0.0.0"
      "--p2p-host=86.3.181.13"
      "--max-peers=50"
      "--host-allowlist=*"
    ];
in
{
  options = {
    services.besu = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "If enabled, start the besu server.";
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

      user = mkOption {
        type = types.str;
        default = "besu";
        description = ''
          User to use when running besu.
        '';
      };

      group = mkOption {
        type = types.str;
        default = "besu";
        description = ''
          Group to use when running besu.
        '';
      };
    };
  };

  config = mkIf cfg.enable {

    networking.firewall.allowedTCPPorts = [ cfg.apiPort cfg.wsPort 30303 ];
    networking.firewall.allowedUDPPorts = [ 30303 ];

    users.users.besu = {
      group = cfg.group;
      description = "besu user";
      home = "/var/lib/besu/";
      extraGroups = [ "docker" ];
    };

    users.groups.besu = {
      name = "besu";
    };

    systemd.services.besu = {
      description = "besu Service";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "network-online.target "];

      serviceConfig = {
        ExecStart = "${pkgs.docker}/bin/docker run --rm -p 9545:9545 -p 30303:30303 -p 8545:8545 -p 8546:8546 --mount type=bind,source=/var/lib/besu,target=/var/lib/besu hyperledger/besu:latest --data-path=/var/lib/besu ${escapeShellArgs cmdArgs}";
        User = cfg.user;
        Group = cfg.group;
      };
    };
  };
}
