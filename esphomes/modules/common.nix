{...}: {
  esphome.requiredSubstitutions = [
    "api_key"
    "ota_key"
    "web_password"
  ];

  esphome.substitutionSources = {
    api_key = {
      type = "sops-yaml";
      file = "secrets/esphome.yaml";
      key = "api_key";
    };
    ota_key = {
      type = "sops-yaml";
      file = "secrets/esphome.yaml";
      key = "ota_key";
    };
    web_password = {
      type = "sops-yaml";
      file = "secrets/esphome.yaml";
      key = "web_password";
    };
  };

  esphome.settings = {
    logger = {};

    api.encryption.key = "\${api_key}";

    ota = [
      {
        platform = "esphome";
        password = "\${ota_key}";
      }
    ];

    preferences.flash_write_interval = "15min";

    web_server = {
      port = 80;
      local = true;
      auth = {
        username = "admin";
        password = "\${web_password}";
      };
    };

    time = [
      {
        platform = "homeassistant";
        id = "homeassistant_time";
      }
    ];

    sensor = [
      {
        platform = "internal_temperature";
        id = "system_internal_temperature";
        name = "Internal Temperature";
        icon = "mdi:oil-temperature";
        device_class = "temperature";
        unit_of_measurement = "°C";
        update_interval = "5s";
      }
      {
        platform = "uptime";
        id = "system_uptime";
        name = "Device Uptime";
        icon = "mdi:power-settings";
        update_interval = "30s";
        state_class = "total_increasing";
        disabled_by_default = true;
      }
    ];

    button = [
      {
        platform = "safe_mode";
        id = "system_safe_mode";
        name = "Enter safe mode";
        icon = "mdi:alert";
        entity_category = "diagnostic";
      }
      {
        platform = "restart";
        id = "system_restart";
        name = "Restart device";
        icon = "mdi:reload";
        entity_category = "config";
      }
      {
        platform = "shutdown";
        id = "system_shutdown";
        name = "Shutdown";
        icon = "mdi:power";
        entity_category = "config";
        disabled_by_default = true;
      }
      {
        platform = "factory_reset";
        id = "factory_reset_btn";
        name = "Factory reset";
        entity_category = "diagnostic";
      }
    ];
  };
}
