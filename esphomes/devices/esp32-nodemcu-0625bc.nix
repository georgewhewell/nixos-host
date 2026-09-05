{...}: {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    ../modules/wifi-idf-tuning.nix
  ];

  esphome.settings = {
    substitutions.name = "esp32-nodemcu-0625bc";

    esphome = {
      name = "\${name}";
      friendly_name = "ESP32 NodeMCU 0625BC";
    };

    # Probed over USB before adoption: ESP32-D0WDQ6 rev 0, 40 MHz crystal,
    # 4 MiB flash, MAC 30:ae:a4:06:25:bc. Keep this pin-free until the old
    # board's eventual job and exact carrier pinout are known.
    esp32 = {
      board = "esp32dev";
      framework.type = "esp-idf";
    };
  };
}
