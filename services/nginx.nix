{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  services.nginx = {
    enable = true;
    statusPage = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    virtualHosts = {
/*      "hydra.satanic.link" = {
         forceSSL = true;
         enableACME = true;
         locations."/" = {
           extraConfig = ''
            # Defer resolving upstream to allow start when upstream down
            resolver 192.168.23.1 valid=30s;
            set $upstream hydra.4a;
            proxy_pass http://$upstream:3000;

            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $remote_addr;
            proxy_set_header X-Forwarded-Proto https;
           '';
         };
      };
   */
    };
  };

  /*
  security.acme.certs."hydra.satanic.link" =
    { email = "georgerw@gmail.com";
      postRun = ''systemctl reload nginx.service'';
    };
*/
  services.prometheus.exporters = {
    nginx = {
      enable = true;
      openFirewall = true;
    };
  };

}
