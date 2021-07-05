{ config, pkgs, ... }:

{

  imports = [
    ./blinds.nix
    ./mqtt.nix
    ./spotcast.nix
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

  services.home-assistant = let
    package = pkgs.home-assistant.override {
      extraPackages = ps: with ps; [
        defusedxml
        python-miio
        netdisco
        aiounifi
        async-upnp-client
        pkgs.python3.pkgs.spotify_token
      ];
    };
  in {
    enable = true;
    openFirewall = true;
    package = package.overrideAttrs(o: {
        doInstallCheck = false;
    });
    /* lovelaceConfig = {
      resources = [
        { url = "local/valetudo-map-card.js";
          type = "module"; }
      ];
    }; */

    config = {
      homeassistant = {
        name = "Home";
        latitude = pkgs.secrets.home-lat;
        longitude = pkgs.secrets.home-lng;
        elevation = "20";
        unit_system = "metric";
        time_zone = "Europe/London";
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
      spotify = {
        client_id = pkgs.secrets.spotify-client-id;
        client_secret = pkgs.secrets.spotify-secret;
      };
      /* cast = {
        media_player = [
          "2563d4dd-39a2-3cb6-77b9-7282624a7ae2"  # tv
          "fdd3040e-0536-b483-b37b-e040ce9ae954"  # speaker
        ];
      }; */
      google_assistant = {
        project_id = "home-9bb96";
      };
      mobile_app = { };
      frontend = { };
      history = { };
      config = { };
      deconz = {
        host = "127.0.0.1";
        port = "8080";
      };
      unifi = {};
      influxdb = { };
      cover = {};
      esphome = {};
      media_player = [
        /* {
          platform = "kodi";
          host = "amlogic-s912";
        } */
      ];
      system_health = { };
      plant =
        let mkPlant = name: {
          sensors = {
            moisture = "sensor.${name}_moisture";
            battery = "sensor.${name}_battery";
            temperature = "sensor.${name}_temperature";
            conductivity = "sensor.${name}_conductivity";
            brightness = "sensor.${name}_light";
          };
        }; in
        {
          hemp = mkPlant "hemp";
          strawberries = mkPlant "strawberries";
          nectarine = mkPlant "nectarine";
          lettuce = mkPlant "lettuce";
        };
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
      }
      /* {
          platform = "ping";
          host = "iphone.lan";
          name = "iphone_ping";
          count = 2;
          scan_interval = 30;
      } */
      ];
      /* icloud = {
        username = pkgs.secrets.icloud-email;
        password = pkgs.secrets.icloud-password;
      };
      automation = [
        {
          alias = "Blink Automatically Take Picture";
          trigger = {
            platform = "time_pattern";
            minutes = "/5";
          };
          action = {
            service = "camera.snapshot";
            data = {
              entity_id = "camera.camera";
              filename = "/mnt/Home/Timelapse/raw_images/kitchen_plant_{{now().year}}{{now().month}}{{now().day}}_{{now().hour}}{{now().minute}}{{now().second}}.jpg";
            };
          };
        }
      ]; */
    };
  };

}
