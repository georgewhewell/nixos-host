{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  services.nginx = {
    enable = true;
    statusPage = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    
    # breaks cache-cache
    # recommendedProxySettings = true;
  };

  services.prometheus.exporters = {
    nginx = {
      enable = true;
      openFirewall = true;
    };
  };

}
