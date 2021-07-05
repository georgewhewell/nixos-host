{ config, pkgs, ... }:

{

  /* package is broken? */
  services.firefox.syncserver = {
    enable = false;
    listen = {
      address = "127.0.0.1";
      port = 5123;
    };
    publicUrl = "https://sync-server.satanic.link";
  };

  security.acme.certs."sync-server.satanic.link".email = "georgerw@gmail.com";
  services.nginx.virtualHosts."sync-server.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:5123";
    };
  };

}
