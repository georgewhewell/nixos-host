{ config, lib, pkgs, ... }:

{
    services.metabase = {
        enable = true;
        listen = {
            ip = "127.0.0.1";
            port = 8321;
        };
    };

    services.nginx.virtualHosts."metabase.satanic.link" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
            proxyPass = "http://127.0.0.1:8321";
        };
    };
}