{...}: {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    ../modules/wifi-idf-tuning.nix
    ../modules/hardware/firefly-pixie.nix
  ];

  esphome.settings = {
    substitutions.name = "firefly-pixie";

    esphome = {
      name = "\${name}";
      friendly_name = "Firefly Pixie";
    };

    font = [
      {
        file = "gfonts://Roboto Mono";
        id = "main_font";
        size = 14;
      }
      {
        file = "gfonts://Roboto Mono";
        id = "small_font";
        size = 10;
      }
    ];

    display = [
      {
        platform = "mipi_spi";
        model = "ST7789V";
        id = "pixie_display";
        dc_pin = "GPIO4";
        reset_pin = "GPIO5";
        data_rate = "40MHz";
        color_order = "bgr";
        dimensions = {
          height = 240;
          width = 240;
        };
        invert_colors = false;
        show_test_card = true;
        update_interval = "1s";
      }
    ];
  };
}
