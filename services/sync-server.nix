{ config, pkgs, ... }: 

{

  services.firefox.syncserver = {
    listen = {
      address = "127.0.0.1";
      port = "5123";
    };
    publicUrl = "https://sync-server.satanic.link";
  };

  services.nginx.virtualHosts."sync-server.satanic.link" = {
     forceSSL = true;
     enableACME = true;
     locations."/" = {
       proxyPass = "http://127.0.0.1:5123";
     };
  };

}
