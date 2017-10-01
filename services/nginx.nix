{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
  };


  security.acme.certs."hydra.satanic.link" =
    { email = "georgerw@gmail.com";
      postRun = ''systemctl reload nginx.service'';
    };

  services.nginx.virtualHosts."hydra.satanic.link" = {
     forceSSL = true;
     enableACME = true;
     locations."/" = {
       proxyPass = "http://localhost:3000";
     };
  };

}
