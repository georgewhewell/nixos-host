{...}: {
  imports = [
    ./esp32-s3.nix
  ];

  esphome.settings = {
    esphome.platformio_options = {
      "board_build.arduino.memory_type" = "qio_opi";
      "board_build.flash_mode" = "dio";
    };

    esp32 = {
      board = "esp32-s3-devkitc-1";
      flash_size = "16MB";
      cpu_frequency = "240MHz";
      framework = {
        version = "latest";
        advanced = {
          compiler_optimization = "perf";
          enable_idf_experimental_features = true;
        };
        sdkconfig_options = {
          CONFIG_ESP32_S3_BOX_BOARD = "y";
          CONFIG_CAMERA_OV5640 = "y";
          CONFIG_CAMERA_OV5647 = "y";
          CONFIG_CAMERA_OV3360 = "y";
          CONFIG_CAMERA_TASK_PINNED_TO_CORE = "CORE1";
          CONFIG_CAMERA_ISR_IRAM_SAFE = "y";
          CONFIG_LCD_CAM_ISR_IRAM_SAFE = "y";
          CONFIG_SPIRAM_USE_MALLOC = "y";
          CONFIG_SPIRAM_MALLOC_ALWAYSINTERNAL = "16384";
        };
      };
    };

    i2c = [
      {
        id = "camera_i2c";
        sda = "GPIO48";
        scl = "GPIO47";
        scan = true;
      }
    ];

    esp32_camera = {
      # Not internal: this is how the camera reaches Home Assistant, as a
      # native ESPHome camera entity — the same way the P4 boards' `camera:`
      # component does (modules/hardware/esp32-p4-evboard.nix). An internal
      # entity is never advertised over the API, so HA never sees it.
      #
      # This does not compete with go2rtc/Frigate: those pull MJPEG from
      # esp32_camera_web_server on :8080 (modules/camera.nix), a separate path
      # from the API. `name: None` takes the device friendly_name.
      name = "None";
      external_clock = {
        pin = "GPIO3";
        frequency = "20MHz";
      };
      i2c_id = "camera_i2c";
      data_pins = ["GPIO41" "GPIO45" "GPIO46" "GPIO42" "GPIO40" "GPIO38" "GPIO15" "GPIO18"];
      vsync_pin = "GPIO1";
      href_pin = "GPIO2";
      pixel_clock_pin = "GPIO39";
      power_down_pin = "GPIO8";
    };

    light = [
      {
        platform = "esp32_rmt_led_strip";
        id = "board_led";
        name = "Status LED";
        pin = "GPIO21";
        num_leds = 1;
        chipset = "WS2812";
        rgb_order = "GRB";
        restore_mode = "RESTORE_DEFAULT_OFF";
        effects = [
          {pulse.name = "Pulse";}
          {strobe.name = "Strobe";}
          {random.name = "Random";}
          {flicker.name = "Flicker";}
          {addressable_rainbow.name = "Rainbow";}
        ];
      }
    ];
  };
}
