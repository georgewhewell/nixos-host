{...}: {
  imports = [
    ../modules/common.nix
    ../modules/hardware/esp32-p4-evboard.nix
    ../modules/hardware/ip101-eth.nix
  ];

  esphome.settings = {
    esphome = {
      name = "esp32-p4-eth-01";
      friendly_name = "esp32-p4-eth-01";
    };

    logger.baud_rate = 0;

    external_components = [
      {
        source = "github://oxan/esphome-stream-server";
        components = ["stream_server"];
      }
    ];

    uart = {
      id = "gps_uart";
      tx_pin = "GPIO47";
      rx_pin = "GPIO48";
      baud_rate = 9600;
    };

    stream_server = {
      uart_id = "gps_uart";
      buffer_size = 8192;
      port = 8888;
    };

    select = [
      {
        id = "change_baud_rate";
        name = "Baud rate";
        platform = "template";
        options = ["2400" "9600" "38400" "57600" "115200" "256000" "512000" "921600"];
        initial_option = "9600";
        optimistic = true;
        restore_value = true;
        internal = false;
        entity_category = "config";
        icon = "mdi:swap-horizontal";
        set_action = [
          {
            lambda = ''
              id(gps_uart).flush();
              uint32_t new_baud_rate = stoi(x);
              ESP_LOGD("change_baud_rate", "Changing baud rate from %i to %i",id(gps_uart).get_baud_rate(),
                        new_baud_rate);
              if (id(gps_uart).get_baud_rate() != new_baud_rate) {
                id(gps_uart).set_baud_rate(new_baud_rate);
                id(gps_uart).load_settings();
              }
            '';
          }
        ];
      }
    ];
  };
}
