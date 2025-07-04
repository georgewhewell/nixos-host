{...}: {
  networking.firewall.allowedTCPPorts = [80 443];

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

  services.nginx.virtualHosts."grafana.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3005";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."home.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    extraConfig = ''
      proxy_buffering off;
    '';
    locations."/" = {
      proxyPass = "http://192.168.23.14:8123";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."radarr.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      extraConfig = ''
        proxy_buffering off;
      '';
      proxyPass = "http://192.168.23.15:7878";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."sonarr.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      extraConfig = ''
        proxy_buffering off;
      '';
      proxyPass = "http://192.168.23.15:8989";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."autobrr.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      extraConfig = ''
        proxy_buffering off;
      '';
      proxyPass = "http://192.168.23.15:7474";
      proxyWebsockets = true;
    };
  };

  services.prometheus.exporters = {
    nginx = {
      enable = true;
      openFirewall = false;
    };
  };

  users.users.nginx = {
    extraGroups = ["acme"];
  };

  services.nginx.virtualHosts."jellyfin.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8096";
      proxyWebsockets = true;
    };
  };
}
