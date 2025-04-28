{...}: {
  imports = [
    ./lights.nix
    ./lovelace.nix
    ./mqtt.nix
    ./vacuum.nix
    ./homekit.nix
  ];

  users.extraUsers."hass".extraGroups = ["dialout" "lp"];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.dbus.implementation = "broker";

  services.esphome = {
    enable = true;
    openFirewall = true;
  };

  services.home-assistant = {
    enable = true;
    openFirewall = true;
    extraPackages = ps:
      with ps; [
        defusedxml
        python-miio
        netdisco
        aiounifi
        aiohomekit
        async-upnp-client
        pyatv
        paho-mqtt
        # withings-api
        # withings-sync
        aiowithings
        python-otbr-api
        pyipp
        pysnmp
        qingping-ble
        xiaomi-ble
        pyxiaomigateway
        brother
        pysmlight
      ];
    config = {
      homeassistant = {
        name = "Home";
        country = "CH";
        # latitude = pkgs.secrets.home-lat;
        # longitude = pkgs.secrets.home-lng;
        elevation = "20";
        unit_system = "metric";
        time_zone = "Europe/Zurich";
        internal_url = "https://home.satanic.link";
        external_url = "https://home.satanic.link";
      };
      http = {
        server_host = "0.0.0.0";
        server_port = 8123;
        use_x_forwarded_for = true;
        trusted_proxies = ["192.168.23.8"];
      };
      mobile_app = {};
      frontend = {};
      history = {};
      config = {};
      zha = {};
      system_health = {};
    };
  };
}
