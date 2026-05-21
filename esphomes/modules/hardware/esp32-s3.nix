{...}: {
  esphome.settings = {
    esp32.framework.type = "esp-idf";

    psram = {
      speed = "80MHz";
      mode = "octal";
      enable_ecc = true;
    };
  };
}
