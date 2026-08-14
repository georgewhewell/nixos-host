{...}: {
  imports = [
    ../camera.nix
  ];

  esphome.settings = {
    esp32 = {
      board = "esp32-p4-evboard";
      flash_size = "16MB";
      framework = {
        type = "esp-idf";
        advanced.enable_idf_experimental_features = true;
        sdkconfig_options = {
          CONFIG_CODEC_I2C_BACKWARD_COMPATIBLE = "no";
          CONFIG_CAMERA_OV5647 = "y";
        };
      };
    };

    psram = {};

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
      {channel = 3; voltage = "2.5V";}
    ];

    # MIPI CSI camera pipeline
    camera = {
      name = "Camera";
      # Milliseconds between frames while streaming (camera_impl.cpp:119 does
      # next_update_ = now + max_update_interval_), NOT a framerate. Default is
      # 100 (10fps); 1000 gives ~1fps, which is the trade for running the
      # sensor at its highest resolution.
      max_update_interval = 1000;
    };

    camera_sensor = {
      type = "mipi_csi";
      # Known-good mode. espressif__esp_cam_sensor 1.5.1 also offers
      # RAW10_1920x1080_30fps and RAW10_1280x960_binning_45fps, but 1080p RAW10
      # was tried on 2026-08-14 and the camera came up "marked FAILED" on all
      # three boards with "STREAM: failed to acquire frame" — the sensor/ISP
      # init fails before the API is up, so the reason is only visible on the
      # serial console. Do not raise this again without a console attached.
      mode = "MIPI_2lane_24Minput_RAW8_800x800_50fps";
    };

    camera_pipeline = [
      {id = "input"; type = "input"; next = "encode";}
      {id = "encode"; type = "output"; camera_encoder_id = "jpeg_encoder";}
    ];

    camera_encoder = {
      id = "jpeg_encoder";
      type = "accelerated_jpeg";
    };

    # I2S audio
    i2s_audio = [
      {
        id = "i2s_output";
        i2s_mclk_pin = "GPIO13";
        i2s_bclk_pin = "GPIO12";
        i2s_lrclk_pin = "GPIO10";
      }
    ];

    audio_dac = [
      {
        platform = "es8311";
        id = "es8311_dac";
        bits_per_sample = "16bit";
        address = "0x18";
        sample_rate = 16000;
        use_mclk = true;
        use_microphone = false;
        mic_gain = "42DB";
      }
    ];

    microphone = [
      {
        platform = "i2s_audio";
        id = "i2s_microphone";
        adc_type = "external";
        i2s_din_pin = "GPIO11";
      }
    ];

    sensor = [
      {
        platform = "sound_level";
        id = "sound_level_id";
        passive = true;
        microphone = {
          microphone = "i2s_microphone";
          channels = 1;
        };
        peak.name = "Peak Loudness";
        rms.name = "Average Loudness";
      }
    ];

    # Speaker amplifier
    output = [
      {platform = "gpio"; id = "pa_enable"; pin = "GPIO53";}
    ];

    switch = [
      {platform = "output"; name = "Speaker Amplifier"; output = "pa_enable";}
    ];
  };
}
