{ config, lib, pkgs, ... }:

{
  jobs.fancontrol = {
    description = "fancontrol daemon";
    exec = "${pkgs.lm_sensors}/sbin/fancontrol /etc/nixos/fancontrol";
  };
}
