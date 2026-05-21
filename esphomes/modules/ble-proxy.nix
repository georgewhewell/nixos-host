{lib, ...}: {
  esphome.settings = {
    esp32_ble_tracker.scan_parameters = {
      interval = "1100ms";
      window = "1100ms";
      active = lib.mkDefault true;
    };

    bluetooth_proxy.active = lib.mkDefault true;
  };
}
