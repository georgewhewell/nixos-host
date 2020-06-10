{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.sunxi-watchdog;
in
{

  options = {

    sunxi-watchdog = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable sunxi hardware watchdog
        '';
      };

      module = {
        type = types.str;
        default = "watchdog";

      };

      grace = mkOption {
        type = types.int;
        default = 10;
        description = ''
          Watchdog lease time
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable rec {

    boot.kernelParams = [ "sunxi_wdt.nowayout=1" ];
    boot.initrd.preLVMCommands = ''
      echo 1 > /dev/watchdog
    '';

    systemd.services.watchdog = {
      description = "watchdog keepalive";
      serviceConfig = {
        Type = "oneshot";
        Restart = "no";
        ExecStart = "/bin/sh -c 'echo 1 > /dev/watchdog'";
      };
    };

    systemd.timers.watchdog = {
      description = "watchdog keepalive";
      partOf = [ "watchdog.service" ];
      wantedBy = [ "sysinit.target" ];
      timerConfig = {
        OnUnitActiveSec = "10";
      };
    };
  };

  meta = { };
}
