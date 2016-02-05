{ config, lib, pkgs, ... }:

{

  systemd.services.fancontrol = {
    description = "fancontrol daemon";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Exec = "${pkgs.lm_sensors}/sbin/fancontrol /etc/nixos/fancontrol";
  };

}
