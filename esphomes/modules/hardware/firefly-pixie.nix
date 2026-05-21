{...}: {
  esphome.settings = {
    esp32 = {
      board = "esp32-c3-devkitm-1";
      flash_size = "16MB";
      framework = {
        type = "esp-idf";
        version = "latest";
      };
    };

    spi = {
      clk_pin = "GPIO6";
      mosi_pin = "GPIO7";
    };

    binary_sensor = [
      {
        platform = "gpio";
        pin = {number = "GPIO10"; mode = "INPUT_PULLUP"; inverted = true;};
        name = "Button 1";
        id = "btn_1";
      }
      {
        platform = "gpio";
        pin = {number = "GPIO8"; mode = "INPUT_PULLUP"; inverted = true;};
        name = "Button 2";
        id = "btn_2";
      }
      {
        platform = "gpio";
        pin = {number = "GPIO3"; mode = "INPUT_PULLUP"; inverted = true;};
        name = "Button 3";
        id = "btn_3";
      }
      {
        platform = "gpio";
        pin = {number = "GPIO2"; mode = "INPUT_PULLUP"; inverted = true;};
        name = "Button 4";
        id = "btn_4";
      }
    ];

    light = [
      {
        platform = "esp32_rmt_led_strip";
        id = "pixie_leds";
        name = "Pixels";
        pin = "GPIO9";
        num_leds = 4;
        chipset = "WS2812";
        rgb_order = "GRB";
        restore_mode = "RESTORE_DEFAULT_OFF";
      }
    ];
  };
}
