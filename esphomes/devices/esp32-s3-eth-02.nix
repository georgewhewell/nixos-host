{...}: {
  imports = [
    ../modules/common.nix
    ../modules/camera.nix
    ../modules/ble-proxy.nix
    ../modules/hardware/waveshare-esp32-s3-cam.nix
    ../modules/hardware/w5500-eth.nix
  ];

  esphome.settings = {
    esphome = {
      name = "esp32-s3-eth-02";
      friendly_name = "esp32-s3-eth-02";
    };

    esp32_ble_tracker.scan_parameters.active = false;

    esp32_camera = {
      resolution = "2560x1920";
      jpeg_quality = 10;
      max_framerate = "5fps";
      idle_framerate = "0.1fps";
      frame_buffer_count = 2;
      vertical_flip = false;
      horizontal_mirror = false;
    };

    # The GPS receiver this board bridged — UART on GPIO33/34, re-served as raw
    # NMEA over TCP:8888 by oxan/esphome-stream-server — is gone, so the uart,
    # stream_server and its external_components entry go with it.
    #
    # Worth remembering if a UART is ever added back here: GPIO33/34 are the
    # wrong pins on this board. It is an ESP32-S3 with *octal* PSRAM
    # (CONFIG_SPIRAM_MODE_OCT, set via memory_type qio_opi in
    # modules/hardware/waveshare-esp32-s3-cam.nix), and octal PSRAM claims
    # GPIO33-37. ESPHome warns about exactly this at compile time.
  };
}
