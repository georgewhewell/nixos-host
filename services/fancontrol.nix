{ config, lib, pkgs, ... }:

{
  jobs.fancontrol = {
    description = "fancontrol daemon";
wantedBy = [ "multi-user.target" ];
    exec = "${pkgs.lm_sensors}/sbin/fancontrol /etc/nixos/fancontrol";
  };
}
