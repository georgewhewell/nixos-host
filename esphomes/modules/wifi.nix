{...}: {
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
      key = "wifi-password";
    };
  };

  esphome.settings = {
    wifi = {
      ssid = "\${wifi_ssid}";
      password = "\${wifi_password}";
      power_save_mode = "none";
      fast_connect = true;
      # No use_address: with this domain the default upload address becomes
      # <name>.lan.satanic.link (unicast DNS from DHCP), no mDNS needed.
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
