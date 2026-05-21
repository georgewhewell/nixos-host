{...}: {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    ../modules/hardware/esp32-p4-evboard.nix
  ];

  esphome.settings = {
    substitutions.name = "esp32-p4-wifi";

    esphome = {
      name = "\${name}";
      friendly_name = "esp32-p4-wifi";
    };

    esp32_hosted = {
      active_high = true;
      variant = "ESP32C6";
      reset_pin = "GPIO54";
      cmd_pin = "GPIO19";
      clk_pin = "GPIO18";
      d0_pin = "GPIO14";
      d1_pin = "GPIO15";
      d2_pin = "GPIO16";
      d3_pin = "GPIO17";
    };
  };
}
