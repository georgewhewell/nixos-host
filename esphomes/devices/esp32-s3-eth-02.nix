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

    external_components = [
      {
        source = "github://oxan/esphome-stream-server";
        components = ["stream_server"];
      }
    ];

    uart = [
      {
        id = "gps_uart";
        tx_pin = "GPIO33";
        rx_pin = "GPIO34";
        baud_rate = 115200;
      }
    ];

    stream_server = [
      {
        uart_id = "gps_uart";
        port = 8888;
      }
    ];
  };
}
