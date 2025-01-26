{pkgs, ...}: {
  imports = [
    ./lights.nix
    ./mqtt.nix
    ./vacuum.nix
    ./homekit.nix
  ];

  users.extraUsers."hass".extraGroups = ["dialout"];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.home-assistant = let
    package = pkgs.home-assistant.override {
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
          withings-api
          withings-sync
          aiowithings
          python-otbr-api
          pyipp
          pysnmp
          qingping-ble
          xiaomi-ble
          pyxiaomigateway
          brother
        ];
    };
  in {
    inherit package;
    enable = true;
    openFirewall = true;
    # package = package.overrideAttrs (o: {
    #   doInstallCheck = false;
    # });
    # lovelaceConfig = {
    #   resources = [
    #     { url = "local/valetudo-map-card.js";
    #       type = "module"; }
    #   ];
    # };

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
        allowlist_external_dirs = [
          "/mnt/Home/Timelapse"
        ];
      };
      http = {
        server_host = "0.0.0.0";
        server_port = 8123;
        use_x_forwarded_for = true;
        trusted_proxies = ["127.0.0.1" "192.168.23.1" "192.168.23.254"];
      };
      mobile_app = {};
      frontend = {};
      history = {};
      config = {};
      zha = {
        zigpy_config.ota.ikea_provider = true;
      };
      system_health = {};
    };
  };
}
