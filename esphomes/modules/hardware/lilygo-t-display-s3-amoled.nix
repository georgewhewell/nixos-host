{...}: {
  imports = [
    ./esp32-s3.nix
  ];

  esphome.settings = {
    esp32 = {
      board = "lilygo-t-display-s3";
      flash_size = "16MB";
    };

    binary_sensor = [
      {
        platform = "gpio";
        pin = {
          number = "GPIO0";
          inverted = true;
        };
        name = "Button 1";
      }
    ];

    spi = {
      id = "qspi_bus";
      type = "quad";
      clk_pin = "GPIO47";
      data_pins = [
        "GPIO18"
        "GPIO7"
        "GPIO48"
        "GPIO5"
      ];
    };

    display = [
      {
        platform = "qspi_dbi";
        model = "RM67162";
        show_test_card = false;
        id = "s3_display";
        auto_clear_enabled = false;
        update_interval = "never";
        dimensions = {
          height = 536;
          width = 240;
        };
        color_order = "rgb";
        brightness = 255;
        cs_pin = "GPIO6";
        reset_pin = "GPIO17";
        rotation = 270;
      }
    ];

    light = [
      {
        platform = "binary";
        name = "Green LED";
        output = "green_led";
      }
    ];

    output = [
      {
        platform = "gpio";
        pin = "GPIO38";
        id = "green_led";
      }
    ];
  };
}
