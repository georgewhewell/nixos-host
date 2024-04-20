{ config, lib, pkgs, ... }:

{
  services.grafana = {
    enable = true;
    addr = "127.0.0.1";
    port = 3005;
    rootUrl = "https://grafana.satanic.link";
    settings = {
      security = {
        admin_password = "/var/lib/grafana/grafana-password.secret";
      };
    };
    auth.anonymous.enable = true;
  };

  systemd.services.grafana.after = [ "grafana-password.secret.service" ];
  deployment.keys =
    {
      "grafana-password.secret" = {
        keyCommand = [ "pass" "grafana.satanic.link" ];
        user = "grafana";
        group = "grafana";
        destDir = "/var/lib/grafana";
        uploadAt = "pre-activation";
      };
    };

  services.nginx.virtualHosts."grafana.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3005";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host grafana.satanic.link;
      '';
    };
  };

}
