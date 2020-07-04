{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.miflora;
in
{

  options.services.miflora = {

    enable = mkEnableOption {
      type = types.bool;
      default = false;
      description = ''
        miflora mqtt daemon
      '';
    };

    sensors = mkOption {
      type = types.attrsOf types.str;
      default = [ ];
      example = { "Poppies@Balcony" = "C4:7C:8D:65:AC:8B"; };
    };

    reporting_method = mkOption {
      type = types.str;
      example = "homeassistant-mqtt";
    };

    period = mkOption {
      type = types.int;
      example = 240;
    };

    hostname = mkOption {
      type = types.str;
    };

    username = mkOption {
      type = types.str;
    };

    password = mkOption {
      type = types.str;
    };

  };

  config = mkIf cfg.enable {

    hardware.bluetooth.enable = true;

    systemd.services.miflora =
      let
        configdir = pkgs.writeTextDir "config.ini" (
          generators.toINI
            { } {
            General = {
              reporting_method = cfg.reporting_method;
            };
            Daemon = {
              period = cfg.period;
            };
            MQTT = {
              hostname = cfg.hostname;
              username = cfg.username;
              password = cfg.password;
            };
            Sensors = cfg.sensors;
          }
        );
      in
      {
        description = "miflora daemon";
        after = [ "network-online.target" ];
        script = ''
          ${pkgs.miflora-mqtt-daemon}/bin/miflora-mqtt-daemon --config_dir ${configdir}
        '';
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "5";
          StartLimitIntervalSec = "0";
          StartLimitBurst = "0";
        };
      };

  };

}
