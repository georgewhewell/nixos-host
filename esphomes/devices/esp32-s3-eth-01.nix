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
      name = "esp32-s3-eth-01";
      friendly_name = "esp32-s3-eth-01";
    };

    esp32_camera = {
      # 2560x1920 (QSXGA) is the largest frame size esp32_camera accepts, and
      # the OV5640 on this board is a 5MP part. Framerate is traded away for it.
      resolution = "2560x1920";
      jpeg_quality = 10;
      max_framerate = "1fps";
      idle_framerate = "0.1fps";
      frame_buffer_count = 2;
      vertical_flip = false;
      horizontal_mirror = false;
    };
  };
}
