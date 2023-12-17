{ config, pkgs, ... }:

{

  imports = [
    ./lights.nix
    ./mqtt.nix
    ./vacuum.nix
    ./homekit.nix
  ];

  services.nginx.virtualHosts."home.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8123";
      extraConfig = ''
        proxy_http_version 1.1;
        proxy_redirect http:// https://;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header X-Real-IP $remote_addr;
        proxy_buffering off;
      '';
    };
  };

  users.extraUsers."hass".extraGroups = [ "dialout" ];

  services.home-assistant =
    let
      package = pkgs.home-assistant.override {
        extraPackages = ps: with ps; [
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
        ];
      };
    in
    {
      enable = true;
      openFirewall = true;
      package = package.overrideAttrs (o: {
        doInstallCheck = false;
      });
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
          trusted_proxies = [ "127.0.0.1" ];
        };
        mobile_app = { };
        frontend = { };
        history = { };
        config = { };
        unifi = { };
        # influxdb = { };
        zha = {
          zigpy_config.ota.ikea_provider = true;
        };
        system_health = { };
      };
    };

}


