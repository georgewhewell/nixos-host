{...}: {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    ../modules/wifi-idf-tuning.nix
  ];

  esphome.settings = {
    substitutions = {
      name = "esp32-c6-lcd-147";
      color_disp_bg = "0x5B2E3D";
      color_label_dark = "0x5F3744";
      color_label_light = "0xFFAFC9";
    };

    esphome = {
      name = "\${name}";
      friendly_name = "\${name}";
    };

    esp32 = {
      board = "esp32-c6-devkitc-1";
      variant = "esp32c6";
      flash_size = "8MB";
      framework = {
        type = "esp-idf";
        sdkconfig_options = {
          CONFIG_ESPTOOLPY_FLASHSIZE_8MB = "y";
        };
      };
    };

    wifi.output_power = "8.5dB";

    spi = [
      {
        clk_pin = "GPIO7";
        mosi_pin = "GPIO6";
      }
    ];

    output = [
      {
        platform = "ledc";
        pin = "GPIO22";
        id = "lcd_bl";
      }
    ];

    light = [
      {
        platform = "esp32_rmt_led_strip";
        id = "status_led";
        name = "Onboard RGB LED";
        pin = "GPIO8";
        num_leds = 1;
        chipset = "ws2812";
        rgb_order = "RGB";
        gamma_correct = 2.8;
        default_transition_length = "0.2s";
      }
    ];
  };
}
