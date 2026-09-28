# Explicit declaration of all sops secrets
# Encrypted YAML files are in this directory
# sops-nix will decrypt them at activation time to /run/secrets/
{
  strix-secure-boot-db-key = {
    sopsFile = ./strix-secure-boot.yaml;
    key = "strix-secure-boot-db-key";
    path = "/run/secrets/strix-secure-boot-db-key";
    mode = "0400";
  };
  # Crypto secrets (trex + router)
  # Used by Lighthouse beacon and Reth execution client for JWT authentication
  lighthouse-jwt = {
    sopsFile = ./crypto.yaml;
    key = "lighthouse-jwt";
    path = "/run/keys/LIGHTHOUSE_JWT";
    mode = "0400";
  };

  # P2Pool environment file for merge mining secrets
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
    # Bind-mounted into the arr-servers container, which owns qui now. The
    # host has no qui user any more, so it cannot be the owner; follow the
    # autobrr precedent above and make it world-readable in /run instead.
    path = "/run/qui-session.secret";
    mode = "0444";
  };

  # ACME DNS-01 credentials (trex)
  # GCP Application Default Credentials (authorized_user) used by lego to solve
  # DNS-01 for the internal-only certs (radarr/sonarr/autobrr). Referenced via
  # GOOGLE_APPLICATION_CREDENTIALS in security.acme; readable by the acme user.
  acme-gcp-adc = {
    sopsFile = ./acme.yaml;
    key = "gcp-adc";
    path = "/run/secrets/acme-gcp-adc";
    owner = "acme";
    group = "acme";
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

  # Bambu Lab LAN access code (router)
  # Authenticates go2rtc's chamber-camera bridge to the A1 mini on TLS :6000.
  # Printed on the printer itself (Settings -> WLAN), so it changes only if the
  # printer is reset or the code is regenerated from its screen.
  bambu-access-code = {
    sopsFile = ./home-automation.yaml;
    key = "bambu-access-code";
    path = "/run/secrets/bambu-access-code";
    owner = "go2rtc";
    group = "go2rtc";
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

  # Control-only backup WAN hosted by the old iPhone on k3's WiFi NIC.
  iphone-hotspot-password = {
    sopsFile = ./iphone-hotspot.yaml;
    key = "iphone-hotspot-password";
    path = "/run/secrets/iphone-hotspot-password";
    mode = "0400";
  };

  # Rescue tunnel identity (k3 -> ax102). k3 is the only holder; the matching
  # public key and ax102's own key live in network.nix `rescue`, which is not
  # secret. wireguard-wg-rescue.service reads these before the network is up,
  # so they must land in /run/secrets rather than a user-owned path.
  wg-rescue-k3-key = {
    sopsFile = ./wireguard-rescue.yaml;
    key = "wg-rescue-k3-key";
    path = "/run/secrets/wg-rescue-k3-key";
    mode = "0400";
  };

  wg-rescue-psk = {
    sopsFile = ./wireguard-rescue.yaml;
    key = "wg-rescue-psk";
    path = "/run/secrets/wg-rescue-psk";
    mode = "0400";
  };

  # 802.11r Fast-Transition key-holder secret. Shared between the router/rock-5b
  # hostapd AP and the OpenWrt UniFi AC-Pro so clients can fast-roam (FT-SAE)
  # between them. Same value must be configured on both APs.
  wifi-ft-key = {
    sopsFile = ./wifi.yaml;
    key = "wifi-ft-key";
    path = "/run/secrets/wifi-ft-key";
    mode = "0400";
  };

  # opencode server password (trex)
  # Auth for the LAN-exposed opencode-server; rendered into an EnvironmentFile
  # as OPENCODE_SERVER_PASSWORD. Without it the serve API is unauthenticated.
  opencode-server-password = {
    sopsFile = ./hellas.yaml;
    # NB: the key inside hellas.yaml is "open-code-password" (as it was added
    # with `sops set`); the nix-side attr name stays opencode-server-password.
    key = "open-code-password";
    path = "/run/secrets/opencode-server-password";
    mode = "0400";
  };

  # kimi-server password (trex)
  # Rendered into an EnvironmentFile as KIMI_CODE_PASSWORD. Without it, kimi's
  # only credential is the random bearer token printed to the journal.
  kimi-web-password = {
    sopsFile = ./hellas.yaml;
    key = "kimi-web-password";
    path = "/run/secrets/kimi-web-password";
    mode = "0400";
  };

  # dsh-web HTTP Basic credentials (trex)
  # A full htpasswd line ("user:$2y$..."), consumed directly as nginx's
  # basicAuthFile. dsh has no login of its own, so this is the only thing
  # standing between the LAN and an agent that can run shell commands as grw.
  dsh-web-htpasswd = {
    sopsFile = ./hellas.yaml;
    key = "dsh-web-htpasswd";
    path = "/run/secrets/dsh-web-htpasswd";
    owner = "nginx";
    mode = "0400";
  };

  # DeepSeek API key (trex)
  # Rendered into an EnvironmentFile as DEEPSEEK_API_KEY for dsh-web. Kept out
  # of ~grw so the key is not readable by every process running as that user.
  deepseek-api-key = {
    sopsFile = ./hellas.yaml;
    key = "deepseek-api-key";
    path = "/run/secrets/deepseek-api-key";
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

  # WireGuard PSK for macbook-air peer
  wg-home-macbook-air-psk = {
    sopsFile = ./wireguard.yaml;
    key = "wg-home-macbook-air-psk";
    path = "/run/secrets/wg-home-macbook-air-psk";
    mode = "0400";
  };
  # BeeGFS cluster shared connection secret (conn.auth). Same bytes on every
  # cluster member: mgmtd (BlueField-2), meta/storage/clients (trex, strix).
  beegfs-conn-auth = {
    sopsFile = ./beegfs.yaml;
    key = "beegfs-conn-auth";
    path = "/run/secrets/beegfs-conn-auth";
    mode = "0400";
  };
}
