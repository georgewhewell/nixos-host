{ pkgs, ... }:

{

  services.miflora = {
    enable = true;
    period = 240;
    reporting_method = "homeassistant-mqtt";
    hostname = "nixhost";
    username = "rw";
    password = pkgs.secrets.mqtt-password;
    sensors = {
      "Poppies@Balcony" = "C4:7C:8D:65:AC:8B";
      "Lettuce@Balcony" = "C4:7C:8D:65:AA:A3";
      "Strawberries@Balcony" = "C4:7C:8D:65:A9:92";
      "Nectarine@Balcony" = "C4:7C:8D:62:87:BA";
    };
  };

}
