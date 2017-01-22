{ options, config, lib, pkgs, ... }:

{
  services.tvheadend.enable = true;
  networking.firewall.allowedTCPPorts = [ 9981 9982 ];
  hardware.firmware = [ pkgs.si2168_02 ];
}
