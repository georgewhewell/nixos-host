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

  };

  config = lib.mkIf cfg.enable {

    # users.optimism = { };

    systemd.services.udpxy = {
      description = "udpxy";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.udpxy}/bin/udpxy -p ${toString cfg.port} -T -s -n -20";
        Restart = "always";
        RestartSec = "5";
      };
    };

  };
}
