{ config, lib, pkgs, ... }:

{
  services.grafana = {
    enable = true;
    addr = "192.168.23.5";
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
}
