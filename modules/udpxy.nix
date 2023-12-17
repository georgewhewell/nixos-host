{ config, lib, pkgs, ... }:
let
  cfg = config.services.udpxy;
in
{

  options.services.udpxy = {
    enable = lib.mkEnableOption "udpxy";
    port = lib.mkOption {
      type = lib.types.int;
      default = 4022;
      description = "UDPXY port";
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open ports in firewall";
    };
  };

  config = lib.mkIf cfg.enable {

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
    networking.firewall.allowedUDPPorts = lib.mkIf cfg.openFirewall [ 5000 ];

    systemd.services.udpxy = {
      description = "udpxy";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.udpxy}/bin/udpxy -p ${toString cfg.port} -T -n -20";
        Restart = "always";
        RestartSec = "5";
      };
    };

  };
}
