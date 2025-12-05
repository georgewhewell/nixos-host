{mkSecret, ...}: {
  # Declare Grafana password secret using sops-nix
  sops.secrets.grafana-password = mkSecret "grafana-password" {};
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
    settings = {
      server = {
        domain = "grafana.satanic.link";
        http_addr = "127.0.0.1";
        http_port = 3005;
        root_url = "https://grafana.satanic.link";
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
      "auth.anonymous".enabled = true;
    };
  };
}
