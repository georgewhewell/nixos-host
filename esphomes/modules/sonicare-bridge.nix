{lib, ...}: {
  esphome.settings = {
    api = {
      custom_services = true;
      homeassistant_services = true;
    };

    esp32.framework.sdkconfig_options = {
      CONFIG_BT_GATTC_MAX_CACHE_CHAR = "80";
      CONFIG_BT_GATTC_NOTIF_REG_MAX = "20";
    };

    esp32_ble = {
      io_capability = "none";
      max_notifications = 20;
    };

    esp32_ble_tracker.scan_parameters = {
      active = lib.mkForce true;
      interval = "211ms";
      window = "120ms";
    };

    external_components = [
      {
        source = {
          type = "git";
          url = "https://github.com/mtheli/philips_sonicare_ble";
          ref = "v0.11.3";
          path = "esphome/components";
        };
        components = ["philips_sonicare"];
        refresh = "0s";
      }
    ];

    philips_sonicare = [
      {
        id = "philips_sonicare_ble";
        on_connect."then" = [
          {"logger.log" = "Connected to Sonicare";}
        ];
        on_disconnect."then" = [
          {"logger.log" = "Disconnected from Sonicare";}
        ];
      }
    ];
  };
}
