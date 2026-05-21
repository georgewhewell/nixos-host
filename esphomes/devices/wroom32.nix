{...}: {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    ../modules/wifi-idf-tuning.nix
    ../modules/ble-proxy.nix
  ];

  esphome.settings = {
    substitutions.name = "wroom32";

    esphome = {
      name = "\${name}";
      friendly_name = "Wroom32";
    };

    esp32 = {
      board = "nodemcu-32s";
      framework.type = "esp-idf";
    };
  };
}
