{...}: {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    ../modules/wifi-idf-tuning.nix
    ../modules/hardware/heltec-lora-v2.nix
  ];

  esphome.settings = {
    substitutions.name = "heltec-lora-v2";

    esphome = {
      name = "\${name}";
      friendly_name = "Office LED Strip 2";
      area = "Office";
    };

    light = [
      {
        platform = "esp32_rmt_led_strip";
        rgb_order = "GRB";
        pin = "GPIO0";
        num_leds = 64;
        chipset = "ws2812";
        name = "Office LED Strip 2";
        id = "office_led_strip_2";
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
                {red = "100%"; green = "100%"; blue = "100%"; num_leds = 5; gradient = true;}
                {red = "0%"; green = "0%"; blue = "0%"; num_leds = 1;}
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
