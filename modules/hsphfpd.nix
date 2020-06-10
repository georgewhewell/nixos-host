{ config, lib, pkgs, ... }:


with lib;
let
  cfg = config.services.hsphfpd;
in
{

  options.services.hsphfpd = {

    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable hsphfpd
      '';
    };

  };

  config = mkIf cfg.enable {

    services.dbus.packages = [ pkgs.hsphfpd ];

    systemd.services.hsphfpd = {
      before = [ "bluetooth.service" "pulseaudio.service" ];
      wantedBy = [ "multi-user.target" ];
      script = ''
        ${pkgs.hsphfpd}/bin/hsphfpd.pl
      '';
    };

  };

}
