{...}: {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    ../modules/wifi-idf-tuning.nix
  ];

  # Bisecting overheat. Re-enable sections one at a time below.
  # Order of suspicion (most → least likely):
  #   1. status_led (esp32_rmt_led_strip on GPIO8 — strapping pin)
  #   2. lcd_bl LEDC + backlight on_boot
  #   3. mipi_spi display @ 10MHz
  #   4. lvgl render loop
  #   5. interval lambda

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
      /*
      on_boot = {
        priority = 800;
        "then" = [
          {
            "light.turn_on" = {
              id = "lcd_backlight";
              brightness = "50%";
            };
          }
        ];
      };
      */
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
        platform = "monochromatic";
        id = "lcd_backlight";
        name = "LCD Backlight";
        output = "lcd_bl";
        restore_mode = "RESTORE_DEFAULT_ON";
      }
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

    display = [
      {
        platform = "mipi_spi";
        id = "main_display";
        model = "ST7789V";
        dimensions = {
          width = 320;
          height = 172;
          offset_width = 0;
          offset_height = 34;
        };
        cs_pin = "GPIO14";
        dc_pin = "GPIO15";
        reset_pin = "GPIO21";
        spi_mode = "MODE3";
        data_rate = "10MHz";
        color_order = "bgr";
        color_depth = 16;
        invert_colors = true;
        auto_clear_enabled = false;
        update_interval = "never";
        show_test_card = true;
      }
    ];

    # lvgl = {
    #   displays = ["main_display"];
    #   buffer_size = "25%";
    #   color_depth = 16;
    #   rotation = 270;
    #   disp_bg_color = "\${color_disp_bg}";
    #   pages = [
    #     {
    #       id = "main_page";
    #       bg_opa = "TRANSP";
    #       widgets = [
    #         {
    #           label = {
    #             align = "CENTER";
    #             text_color = "\${color_label_dark}";
    #             text = "00:00:00";
    #           };
    #         }
    #         {
    #           label = {
    #             id = "clock_label";
    #             align = "CENTER";
    #             text_color = "\${color_label_light}";
    #             text = "--:--:--";
    #           };
    #         }
    #       ];
    #     }
    #   ];
    # };

    # interval = [
    #   {
    #     interval = "1s";
    #     "then" = [
    #       {
    #         lambda = ''
    #           auto now = id(homeassistant_time).now();
    #           if (!now.is_valid()) {
    #             lv_label_set_text(id(clock_label), "--:--:--");
    #             return;
    #           }
    #           char buffer[9];
    #           now.strftime(buffer, sizeof(buffer), "%H:%M:%S");
    #           lv_label_set_text(id(clock_label), buffer);
    #         '';
    #       }
    #     ];
    #   }
    # ];
  };
}
