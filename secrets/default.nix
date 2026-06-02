# Explicit declaration of all sops secrets
# Encrypted YAML files are in this directory
# sops-nix will decrypt them at activation time to /run/secrets/
{
  # Crypto secrets (trex + router)
  # Used by Lighthouse beacon and Reth execution client for JWT authentication
  lighthouse-jwt = {
    sopsFile = ./crypto.yaml;
    key = "lighthouse-jwt";
    path = "/run/keys/LIGHTHOUSE_JWT";
    mode = "0400";
  };

  # P2Pool environment file for merge mining secrets (router)
  # Contains: TARI_WALLET_ADDRESS=<tari address>
  p2pool-env = {
    sopsFile = ./crypto.yaml;
    key = "p2pool-env";
    path = "/run/secrets/p2pool-env";
    owner = "p2pool";
    group = "p2pool";
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

  # Qui session secret (trex)
  # Used by qui alternative qBittorrent webUI for session authentication
  qui-session = {
    sopsFile = ./media.yaml;
    key = "qui-session";
    path = "/run/secrets/qui-session";
    owner = "qui";
    group = "qui";
    mode = "0400";
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

  # Used by Grafana for signing cookies and other internal secrets
  grafana-secret-key = {
    sopsFile = ./monitoring.yaml;
    key = "grafana-secret-key";
    path = "/run/secrets/grafana-secret-key";
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };

  # NUT UPS monitor password (trex)
  nut-upsmon = {
    sopsFile = ./monitoring.yaml;
    key = "nut-upsmon";
    path = "/run/secrets/nut-upsmon";
    owner = "nutmon";
    group = "nutmon";
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

  # Home Assistant Prometheus token (trex - for victoriametrics scraping)
  hass-prometheus-token = {
    sopsFile = ./monitoring.yaml;
    key = "hass-prometheus-token";
    path = "/run/secrets/hass-prometheus-token";
    owner = "victoriametrics";
    group = "victoriametrics";
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

  # Backup WiFi password (VM4588425)
  wifi-password-backup = {
    sopsFile = ./wifi.yaml;
    key = "wifi-password-backup";
    path = "/run/secrets/wifi-password-backup";
    mode = "0400";
  };

  # Hugging Face token (trex + fuckup)
  # Used by hellas executor for gated model downloads
  hf-token = {
    sopsFile = ./hellas.yaml;
    key = "hf-token";
    path = "/run/secrets/hf-token";
    mode = "0400";
  };

  # Nix binary cache signing key (trex only)
  # Used by nix-daemon (secret-key-files) and services.nix-serve to sign
  # locally-built store paths so `nix copy` to other hosts is accepted
  # without --no-check-sigs. Public key lives in modules/nix.nix's
  # trusted-public-keys list.
  nix-cache-key = {
    sopsFile = ./nix.yaml;
    key = "nix-cache-priv-key";
    path = "/run/secrets/nix-cache-key";
    mode = "0400";
  };

  # WireGuard (router)
  # Private key for the wg-home interface
  # Note: path must be flat (no subdirs) to avoid sops-nix symlink bug
  wg-home-key = {
    sopsFile = ./wireguard.yaml;
    key = "wg-home-router-private";
    path = "/run/secrets/wg-home-key";
    mode = "0400";
  };

  # Private key for the Hydra-only builder tunnel on the router.
  wg-hydra-builders-router-key = {
    sopsFile = ./wireguard.yaml;
    key = "wg-hydra-builders-router-private";
    path = "/run/secrets/wg-hydra-builders-router-key";
    mode = "0400";
  };

  # WireGuard PSK shared by ax102 and the home router for the Hydra builder tunnel.
  wg-hydra-builders-psk = {
    sopsFile = ./wireguard.yaml;
    key = "wg-hydra-builders-psk";
    path = "/run/secrets/wg-hydra-builders-psk";
    mode = "0400";
  };

  # WireGuard PSK for iOS peer
  wg-home-ios-psk = {
    sopsFile = ./wireguard.yaml;
    key = "wg-home-ios-psk";
    path = "/run/secrets/wg-home-ios-psk";
    mode = "0400";
  };

  # WireGuard PSK for macbook-pro peer
  wg-home-macbook-pro-psk = {
    sopsFile = ./wireguard.yaml;
    key = "wg-home-macbook-pro-psk";
    path = "/run/secrets/wg-home-macbook-pro-psk";
    mode = "0400";
  };
}
