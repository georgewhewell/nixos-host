{
  lib,
  pkgs,
  config,
  mkSecret,
  ...
}: let
  useNetworkManager = config.networking.networkmanager.enable;
  primarySsid = "Radio Free Europe";
  backupSsid = "VM4588425";
in {
  # Only configure WiFi if NetworkManager is not enabled
  # NetworkManager users should configure WiFi manually
  config = lib.mkIf (!useNetworkManager) {
    # WiFi passwords managed via sops-nix
    sops.secrets.wifi-password = mkSecret "wifi-password" {};
    sops.secrets.wifi-password-backup = mkSecret "wifi-password-backup" {};

    hardware.wirelessRegulatoryDatabase = true;

    # Generate wpa_supplicant secrets file from sops secrets
    systemd.services.wpa-supplicant-secrets = let
      # Service names depend on whether interfaces are specified
      ifaces = config.networking.wireless.interfaces;
      serviceNames =
        if ifaces == []
        then ["wpa_supplicant.service"]
        else map (i: "wpa_supplicant-${i}.service") ifaces;
    in {
      description = "Generate wpa_supplicant secrets file from sops";
      wantedBy = serviceNames;
      before = serviceNames;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /run/secrets-wpa
        echo "wifi-password=$(cat ${config.sops.secrets.wifi-password.path})" > /run/secrets-wpa/wpa_supplicant.conf
        echo "wifi-password-backup=$(cat ${config.sops.secrets.wifi-password-backup.path})" >> /run/secrets-wpa/wpa_supplicant.conf
        chown root:wpa_supplicant /run/secrets-wpa/wpa_supplicant.conf
        chmod 0640 /run/secrets-wpa/wpa_supplicant.conf
      '';
    };

    # Use wpa_supplicant for WiFi
    networking.wireless = {
      enable = true;
      secretsFile = "/run/secrets-wpa/wpa_supplicant.conf";
      networks."${primarySsid}" = {
        pskRaw = "ext:wifi-password";
        priority = 10;
      };
      networks."${backupSsid}-5G" = {
        pskRaw = "ext:wifi-password-backup";
        priority = 1;
      };
      networks."${backupSsid}" = {
        pskRaw = "ext:wifi-password-backup";
        priority = 5;
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
