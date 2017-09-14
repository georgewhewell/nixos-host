{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 3001 ];

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
      proxyPass = "http://localhost:3001";
    };
  };
}
