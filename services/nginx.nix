{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  security.acme = {
    acceptTerms = true;
    defaults.email = "georgerw@gmail.com";
  };

  services.nginx = {
    enable = true;
    statusPage = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    # breaks cache-cache
    /* recommendedProxySettings = true; */
  };

  services.prometheus.exporters = {
    nginx = {
      enable = true;
      openFirewall = true;
    };
  };

  users.users.nginx = {
    extraGroups = [ "acme" ];
  };

  services.nginx.virtualHosts."jellyfin.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://192.168.23.254:8096";
      proxyWebsockets = true;
    };
  };

}
