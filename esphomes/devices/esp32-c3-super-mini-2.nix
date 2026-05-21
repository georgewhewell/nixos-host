{...}: {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    ../modules/wifi-idf-tuning.nix
  ];

  esphome.settings = {
    substitutions.name = "esp32-c3-super-mini-2";

    esphome = {
      name = "\${name}";
      friendly_name = "Office LED Strip 1";
      area = "Office";
    };

    esp32 = {
      board = "esp32-c3-devkitm-1";
      framework = {
        type = "esp-idf";
        version = "latest";
        sdkconfig_options = {
          CONFIG_HTTPD_MAX_REQ_HDR_LEN = "1024";
          CONFIG_HTTPD_MAX_URI_LEN = "512";
          CONFIG_HTTPD_MAX_RESP_HDR_LEN = "1024";
          CONFIG_ESP_MAIN_TASK_STACK_SIZE = "8192";
          CONFIG_FREERTOS_TIMER_TASK_STACK_DEPTH = "3072";
        };
      };
    };

    light = [
      {
        platform = "esp32_rmt_led_strip";
        rgb_order = "GRB";
        pin = "GPIO4";
        num_leds = 64;
        chipset = "ws2812";
        name = "Office LED Strip 1";
        id = "office_led_strip_1";
        effects = [
          {addressable_rainbow = {};}
          {
            addressable_rainbow = {
              name = "Rainbow Effect With Custom Values";
              speed = 10;
              width = 50;
            };
          }
          {addressable_color_wipe = {};}
          {
            addressable_color_wipe = {
              name = "Color Wipe Effect With Custom Values";
              colors = [
                {
                  red = "100%";
                  green = "100%";
                  blue = "100%";
                  num_leds = 5;
                  gradient = true;
                }
                {
                  red = "0%";
                  green = "0%";
                  blue = "0%";
                  num_leds = 1;
                }
              ];
              add_led_interval = "100ms";
              reverse = false;
            };
          }
          {addressable_scan = {};}
          {
            addressable_scan = {
              name = "Scan Effect With Custom Values";
              move_interval = "100ms";
              scan_width = 1;
            };
          }
          {addressable_twinkle = {};}
          {addressable_random_twinkle = {};}
          {addressable_fireworks = {};}
          {addressable_flicker = {};}
        ];
      }
    ];
  };
}
