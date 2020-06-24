{ config, lib, pkgs, ... }:

{
  services.grafana = {
    enable = true;
    addr = "127.0.0.1";
    port = 3005;
    rootUrl = "https://grafana.satanic.link";
    security = {
      adminUser = "admin";
      adminPassword = pkgs.secrets.grafana-admin-password;
    };
    auth.anonymous.enable = true;
  };

  security.acme.certs."grafana.satanic.link" = {
    email = "georgerw@gmail.com";
    postRun = ''systemctl reload nginx.service'';
  };

  services.nginx.virtualHosts."grafana.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3005";
    };
  };

}
