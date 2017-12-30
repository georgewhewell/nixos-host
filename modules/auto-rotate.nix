{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.hardware.auto-rotate;
in
  {
    options.hardware.auto-rotate = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to start the auto-rotate daemon
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.auto-rotate;
        defaultText = "pkgs.auto-rotate";
        description = ''
          Which auto-rotate package to use.
        '';
      };
    };

    config = mkIf cfg.enable {
      hardware.sensor.iio.enable = true;
      environment.systemPackages = [ cfg.package ];
      systemd.user.services.auto-rotate = {
        description = "Auto-rotate daemon";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${cfg.package}/bin/auto-rotate";
          Type = "forking";
        };
      };
    };
    meta = {};
  }
