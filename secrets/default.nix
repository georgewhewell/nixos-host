# Explicit declaration of all sops secrets
# Encrypted YAML files are in this directory
# sops-nix will decrypt them at activation time to /run/secrets/
{
  # Crypto secrets (trex)
  # Used by Lighthouse beacon and Reth execution client for JWT authentication
  lighthouse-jwt = {
    sopsFile = ./crypto.yaml;
    key = "lighthouse-jwt";
    path = "/run/keys/LIGHTHOUSE_JWT";
    mode = "0400";
  };

  # GitHub runner secrets (trex)
  # Used by containerized GitHub Actions runners
  gh-runner-grw = {
    sopsFile = ./github-runners.yaml;
    key = "gh-runner-grw";
    path = "/run/gh-runner-georgewhewell-nixos-host.secret";
    mode = "0777"; # Permissive for container bind mount
  };

  gh-runner-hellas-a = {
    sopsFile = ./github-runners.yaml;
    key = "gh-runner-hellas-a";
    path = "/run/gh-runner-hellas-a.secret";
    mode = "0777";
  };

  gh-runner-hellas-b = {
    sopsFile = ./github-runners.yaml;
    key = "gh-runner-hellas-b";
    path = "/run/gh-runner-hellas-b.secret";
    mode = "0777";
  };

  gh-runner-hellas-c = {
    sopsFile = ./github-runners.yaml;
    key = "gh-runner-hellas-c";
    path = "/run/gh-runner-hellas-c.secret";
    mode = "0777";
  };

  # Media secrets (trex)
  # Used by Autobrr in the arr-servers container
  autobrr = {
    sopsFile = ./media.yaml;
    key = "autobrr";
    path = "/run/autobrr.secret";
    mode = "0777"; # Permissive for container bind mount
  };

  # Monitoring secrets (trex)
  # Used by Grafana for admin authentication
  grafana-password = {
    sopsFile = ./monitoring.yaml;
    key = "grafana-password";
    path = "/var/lib/grafana/grafana-password.secret";
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };

  # Home automation secrets (router)
  # Used by Mosquitto MQTT broker for authentication
  mosquitto-password = {
    sopsFile = ./home-automation.yaml;
    key = "mosquitto-password";
    path = "/run/secrets/mosquitto-password";
    owner = "mosquitto";
    group = "mosquitto";
    mode = "0400";
  };

  # WiFi secrets (router)
  # Used by hostapd for WiFi AP authentication
  wifi-password = {
    sopsFile = ./wifi.yaml;
    key = "wifi-password";
    path = "/run/secrets/wifi-password";
    mode = "0400";
  };

  # WireGuard (router)
  # Private key for the wg-home interface
  wg-home-key = {
    sopsFile = ./wireguard.yaml;
    key = "wg-home-router-private";
    path = "/run/secrets/wireguard/wg-home.key";
    mode = "0400";
  };
}
