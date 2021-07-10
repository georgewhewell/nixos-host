{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  security.acme = {
    acceptTerms = true;
    email = "georgerw@gmail.com";
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

  security.acme.certs."jellyfin.satanic.link" = {
    email = "georgerw@gmail.com";
    postRun = ''systemctl reload nginx.service'';
  };

  services.nginx.virtualHosts."jellyfin.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://fuckup.lan:8096";
    };
  };

}
