{...}: {
  services.postgresql = {
    enable = true;
    ensureUsers = [
      {
        name = "grafana";
        ensureDBOwnership = true;
      }
    ];
    ensureDatabases = ["grafana"];
  };

  services.grafana = {
    enable = true;
    addr = "127.0.0.1";
    port = 3005;
    rootUrl = "https://grafana.satanic.link";
    settings = {
      server = {
        domain = "grafana.satanic.link";
      };
      database = {
        type = "postgres";
        host = "/run/postgresql";
        name = "grafana";
        user = "grafana";
      };
      security = {
        admin_user = "admin";
        admin_password_file = "/var/lib/grafana/grafana-password.secret";
        admin_email = "accounts@hellas.ai";
      };
    };
    auth.anonymous.enable = true;
  };

  systemd.services.grafana.after = ["grafana-password.secret.service"];
  deployment.keys = {
    "grafana-password.secret" = {
      keyCommand = ["pass" "grafana.satanic.link"];
      user = "grafana";
      group = "grafana";
      destDir = "/var/lib/grafana";
      uploadAt = "pre-activation";
    };
  };
}
