{ config, pkgs, ... }:

{
  services.avahi = {
    enable = true;
    reflector = true;
  };

  networking.firewall.allowedUDPPorts = [ 5353 ];
  networking.firewall.allowedTCPPorts = [ 21063 ];

  services.home-assistant.config.zeroconf = { };
  services.home-assistant.config.homekit = {
    filter = {
      include_domains = [ "light" ];
    };
  };

  services.home-assistant.config.logger = {
    default = "info";
  };
}
