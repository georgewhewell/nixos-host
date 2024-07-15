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
    recommendedProxySettings = true;
  };

  fileSystems."/var/www/static" =
    {
      device = "nvpool/root/www";
      fsType = "zfs";
      options = [ "nofail" ];
    };

  services.nginx.virtualHosts."static.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      root = "/var/www/static";
    };
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
      proxyPass = "http://192.168.23.206:8096";
      proxyWebsockets = true;
    };
  };
}
