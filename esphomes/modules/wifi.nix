{
  config,
  lib,
  ...
}: let
  hasNameSub = lib.hasAttrByPath ["esphome" "settings" "substitutions" "name"] config;
in {
  assertions = [
    {
      assertion = hasNameSub;
      message = ''
        The ESPHome wifi module requires `esphome.settings.substitutions.name`
        because it sets `wifi.use_address = "''${name}.local"`.
      '';
    }
  ];

  esphome.requiredSubstitutions = [
    "wifi_ssid"
    "wifi_password"
  ];

  esphome.substitutionSources = {
    wifi_ssid = {
      type = "sops-yaml";
      file = "secrets/esphome.yaml";
      key = "wifi_ssid";
    };
    wifi_password = {
      type = "sops-yaml";
      file = "secrets/wifi.yaml";
      key = "wifi-password-backup";
    };
  };

  esphome.settings = {
    wifi = {
      ssid = "\${wifi_ssid}";
      password = "\${wifi_password}";
      power_save_mode = "none";
      fast_connect = true;
      use_address = "\${name}.local";
      domain = ".lan.satanic.link";
    };

    sensor = [
      {
        platform = "wifi_signal";
        name = "WiFi Signal dB";
        id = "wifi_signal_db";
        update_interval = "10s";
      }
      {
        platform = "copy";
        source_id = "wifi_signal_db";
        name = "WiFi Signal Percent";
        id = "wifi_signal_percent";
        filters = [
          {lambda = "return min(max(2 * (x + 100.0), 0.0), 100.0);";}
        ];
        unit_of_measurement = "%";
        entity_category = "diagnostic";
        device_class = "";
      }
    ];

    text_sensor = [
      {
        platform = "wifi_info";
        ip_address = {
          id = "wifi_info_ip_address";
          name = "IP Address";
        };
        ssid = {
          id = "wifi_info_ssid";
          name = "Connected SSID";
        };
        bssid.name = "Connected BSSID";
        mac_address.name = "Mac Wifi Address";
        scan_results.name = "Latest Scan Results";
        dns_address.name = "DNS Address";
      }
    ];
  };
}
