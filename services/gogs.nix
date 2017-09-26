{ config, lib, pkgs, ... }:

{

  security.acme.certs."git.satanic.link" = {
     email = "georgerw@gmail.com";
     postRun = ''systemctl reload nginx.service'';
  };

  services.gogs = {
    enable = true;
    useWizard = true;
  };

  services.nginx.virtualHosts."git.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3001";
    };
  };
}
