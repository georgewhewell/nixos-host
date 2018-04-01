{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  services.nginx = {
    enable = true;
    statusPage = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    virtualHosts = {
      "hydra.satanic.link" = {
         forceSSL = true;
         enableACME = true;
         locations."/" = {
           proxyPass = "http://hydra.4a:3000";
         };
      };
      "bstream.satanic.link" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "https://stream.binance.com:9443";
          extraConfig = ''
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
          '';
        };
      };

    };
  };

  security.acme.certs."hydra.satanic.link" =
    { email = "georgerw@gmail.com";
      postRun = ''systemctl reload nginx.service'';
    };

  security.acme.certs."bstream.satanic.link" =
    { email = "georgerw@gmail.com";
      postRun = ''systemctl reload nginx.service'';
    };

  services.prometheus.exporters = {
    nginx = {
      enable = true;
      openFirewall = true;
    };
  };

}
