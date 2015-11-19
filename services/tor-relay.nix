{ config, lib, pkgs, ... }:

{
  services.tor.enable = true;
  services.tor.relay.enable = true;
  services.tor.relay.nickname = "tsardotsu";
  services.tor.relay.portSpec = "9001";
  networking.firewall.allowedTCPPorts = [ 9001 ];
  networking.firewall.allowedUDPPorts = [ 9001 ];
}

