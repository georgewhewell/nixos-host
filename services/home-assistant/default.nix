{ config, pkgs, ... }:

{

  imports = [
    ./mqtt.nix
    ./vacuum.nix
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

  services.influxdb.enable = true;

  services.home-assistant =
    let
      package = pkgs.home-assistant.override {
        extraPackages = ps: with ps; [
          defusedxml
          python-miio
          netdisco
          aiounifi
          async-upnp-client
          # pkgs.python3.pkgs.spotify_token
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
        circadian_lighting = { };
        switch = [{ platform = "circadian_lighting"; lights_ct = [ "light.bedroom_ceiling_light" "light.hallway_ceiling_light" "light.office_ceiling_light" ]; }];
        mobile_app = { };
        frontend = { };
        history = { };
        config = { };
        unifi = { };
        influxdb = { };
        cover = { };
        esphome = { };
        zha = { };
        system_health = { };
        binary_sensor = [{
          name = "George Presence";
          platform = "bayesian";
          prior = 0.5;
          probability_threshold = 0.9;
          observations = [
            {
              entity_id = "device_tracker.georgesplewatch";
              prob_given_true = "0.8";
              prob_given_false = "0.2";
              platform = "state";
              to_state = "home";
            }
            {
              entity_id = "device_tracker.iphone_2";
              prob_given_true = "0.8";
              prob_given_false = "0.2";
              platform = "state";
              to_state = "home";
            }
          ];
        }];
      };
    };

}


