{...}: {
  esphome.settings = {
    esp32 = {
      board = "heltec_wifi_lora_32";
      flash_size = "4MB";
      framework = {
        type = "esp-idf";
        sdkconfig_options = {
          CONFIG_XTAL_FREQ_26 = "y";
          CONFIG_XTAL_FREQ = "26";
        };
      };
    };

    logger = {
      hardware_uart = "UART0";
      baud_rate = 115200;
    };
  };
}
