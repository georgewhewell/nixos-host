{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.radeon-profile-daemon;
in
{

  options.services.radeon-profile-daemon = {

    enable = mkEnableOption {
      type = types.bool;
      default = false;
      description = ''
        radeon-profile-daemon
      '';
    };

  };

  config = mkIf cfg.enable {

    systemd.services.radeon-profile-daemon = {
      description = "radeon-profile-daemon";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.radeon-profile-daemon}/bin/radeon-profile-daemon";
        PrivateTmp = "yes";
        PrivateDevices = "yes";
      };
    };

  };

}
