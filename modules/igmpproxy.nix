{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.services.igmpproxy;
in
{

  options = {
    services.igmpproxy = {
      enable = mkEnableOption (lib.mdDoc "start igmpproxy daemon");
      config = lib.mkOption {
        type = lib.types.lines;
        default = '''';
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services.igmpproxy =
      let cfgFile = pkgs.writeText "igmpproxy.conf" cfg.config;
      in {
        description = "igmpproxy";
        wantedBy = [ "multi-user.target" ];
        after = [ "br0.lan-netdev.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.igmpproxy}/bin/igmpproxy ${cfgFile} -n -v";
        };
      };
  };

}
