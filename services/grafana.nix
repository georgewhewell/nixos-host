{mkSecret, network, ...}: let
  domain = network.publicFqdn "grafana";
in {
  # Declare Grafana secrets using sops-nix
  sops.secrets.grafana-password = mkSecret "grafana-password" {};
  sops.secrets.grafana-secret-key = mkSecret "grafana-secret-key" {};
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
    provision.datasources.settings.datasources = [
      {
        name = "prometheus";
        type = "prometheus";
        uid = "feit1tygbp81sc";
        url = "http://127.0.0.1:8428";
        isDefault = true;
        jsonData.httpMethod = "POST";
      }
    ];
    provision.dashboards.settings.providers = [
      {
        name = "nixos-config";
        options.path = ./grafana-dashboards;
        allowUiUpdates = true;
      }
    ];
    settings = {
      server = {
        inherit domain;
        http_addr = "127.0.0.1";
        http_port = 3005;
        root_url = "https://${domain}";
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
        secret_key = "$__file{/run/secrets/grafana-secret-key}";
      };
      "auth.anonymous".enabled = true;
    };
  };
}
