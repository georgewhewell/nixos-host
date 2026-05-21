{...}: {
  esphome.settings = {
    esphome = {
      name = "esp32-p4-h264-test";
      friendly_name = "esp32-p4-h264-test";
    };

    esp32 = {
      variant = "esp32p4";
      cpu_frequency = "400MHz";
      flash_size = "32MB";
      framework = {
        type = "esp-idf";
        advanced.enable_idf_experimental_features = true;
        sdkconfig_options = {
          CONFIG_CODEC_I2C_BACKWARD_COMPATIBLE = "no";
          CONFIG_CAMERA_OV5647 = "y";
        };
      };
    };

    psram = {
      mode = "hex";
      speed = "200MHz";
    };

    logger.hardware_uart = "USB_CDC";

    external_components = [
      {
        source = {
          type = "local";
          path = "external-components";
        };
        components = [
          "camera"
          "camera_encoder"
          "camera_pipeline"
          "camera_sensor"
        ];
      }
    ];

    i2c = [
      {
        id = "i2c_bus";
        sda = "GPIO7";
        scl = "GPIO8";
        scan = true;
        frequency = "400kHz";
      }
    ];

    esp_ldo = [
      {
        channel = 3;
        voltage = "2.5V";
      }
    ];

    camera.name = "Camera";

    camera_sensor = {
      type = "mipi_csi";
      mode = "MIPI_2lane_24Minput_RAW8_800x800_50fps";
    };

    camera_pipeline = [
      {
        id = "input";
        type = "input";
        next = "encode";
      }
      {
        id = "encode";
        type = "output";
        camera_encoder_id = "h264_encoder";
      }
    ];

    camera_encoder = {
      id = "h264_encoder";
      type = "h264";
      width = 640;
      height = 480;
      fps = 25;
      gop = 25;
      bitrate = 1000000;
      buffer_size = 1048576;
    };
  };
}
