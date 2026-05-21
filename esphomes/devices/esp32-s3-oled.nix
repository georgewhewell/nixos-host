{...}: {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    ../modules/wifi-idf-tuning.nix
  ];

  esphome.settings = {
    substitutions.name = "esp32-s3-nano-oled";

    esphome = {
      name = "\${name}";
      friendly_name = "ESP32-S3-Nano-OLED";
    };

    esp32 = {
      variant = "esp32c3";
      framework.type = "esp-idf";
    };

    i2c = [
      {
        sda = "GPIO5";
        scl = "GPIO6";
        frequency = "25kHz";
        scan = true;
      }
    ];

    output = [
      {
        platform = "ledc";
        pin.number = "GPIO4";
        frequency = "25kHz";
        id = "fan_pwm";
      }
      {
        platform = "gpio";
        pin = {
          number = "GPIO8";
          inverted = true;
        };
        id = "gpio_8";
      }
    ];

    fan = [
      {
        platform = "speed";
        output = "fan_pwm";
        name = "Cooling Fan";
      }
    ];

    light = [
      {
        platform = "binary";
        name = "Onboard LED";
        output = "gpio_8";
        restore_mode = "ALWAYS_OFF";
      }
    ];

    sensor = [
      {
        platform = "pulse_counter";
        pin = {
          number = "GPIO3";
          mode = {
            input = true;
            pullup = true;
          };
        };
        name = "Fan RPM";
        unit_of_measurement = "RPM";
        update_interval = "5s";
        filters = [
          {multiply = 0.5;}
        ];
      }
    ];

    display = [
      {
        platform = "ssd1306_i2c";
        model = "SSD1306 72x40";
        rotation = 0;
        update_interval = "60s";
        offset_y = 0;
        offset_x = 0;
        invert = false;
        address = "0x3C";
        show_test_card = true;
      }
    ];
  };
}
