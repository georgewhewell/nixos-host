{...}: {
  imports = [
    ../ethernet-info.nix
  ];

  esphome.settings = {
    esp32 = {
      board = "esp-wrover-kit";
      framework.type = "esp-idf";
    };

    ethernet = {
      type = "LAN8720";
      mdc_pin = "GPIO23";
      mdio_pin = "GPIO18";
      clk_mode = "GPIO0_IN";
      phy_addr = 1;
      power_pin = "GPIO16";
    };
  };
}
