{
  lib,
  pkgs,
  config,
  mkSecret,
  ...
}: let
  useNetworkManager = config.networking.networkmanager.enable;
  ssid = "Radio Free Europe";
in {
  # Only configure WiFi if NetworkManager is not enabled
  # NetworkManager users should configure WiFi manually
  config = lib.mkIf (!useNetworkManager) {
    # WiFi password managed via sops-nix
    sops.secrets.wifi-password = mkSecret "wifi-password" {};

    hardware.wirelessRegulatoryDatabase = true;

    # Generate wpa_supplicant secrets file from sops secret
    systemd.services.wpa-supplicant-secrets = {
      description = "Generate wpa_supplicant secrets file from sops";
      wantedBy = ["wpa_supplicant.service"];
      before = ["wpa_supplicant.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /run/secrets-wpa
        echo "wifi-password=$(cat ${config.sops.secrets.wifi-password.path})" > /run/secrets-wpa/wpa_supplicant.conf
        chmod 0600 /run/secrets-wpa/wpa_supplicant.conf
      '';
    };

    # Use wpa_supplicant for WiFi
    networking.wireless = {
      enable = true;
      secretsFile = "/run/secrets-wpa/wpa_supplicant.conf";
      networks."${ssid}" = {
        pskRaw = "ext:wifi-password";
      };
    };

    # systemd-networkd configuration for WiFi
    systemd.network.networks."20-wifi" = {
      matchConfig.Type = "wlan";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      dhcpV4Config.RouteMetric = 200;
      linkConfig.RequiredForOnline = "routable";
    };
  };
}
