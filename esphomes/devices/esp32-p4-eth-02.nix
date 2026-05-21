{...}: {
  imports = [
    ../modules/common.nix
    ../modules/hardware/esp32-p4-evboard.nix
    ../modules/hardware/ip101-eth.nix
  ];

  esphome.settings = {
    esphome = {
      name = "esp32-p4-eth-02";
      friendly_name = "esp32-p4-eth-02";
    };
  };
}
