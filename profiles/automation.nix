{ config, pkgs, ... }:

{

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  systemd.services.am43-ctrl = {
    description = "blind controller";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.ExecStart = ''
      ${pkgs.am43-ctrl}/bin/am43ctrl --mqtt-url mqtt://rw:${pkgs.secrets.mqtt-password}@nixhost.lan 02:c4:da:36:73:79 02:be:75:37:b6:0a
    '';
  };

  services.udev.extraRules = ''
    SUBSYSTEM==“tty”, ATTRS{idVendor}==“0658”, ATTRS{idProduct}==“0200”, SYMLINK+=“zwave”
  '';

  users.users."deconz" = {
    createHome = true;
    isNormalUser = true;
    group = "dialout";
    home = "/home/deconz";
  };

  systemd.services.deconz = {
    enable = true;
    description = "deconz";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    stopIfChanged = false;
    serviceConfig = {
      ExecStart = "${pkgs.deCONZ.deCONZ}/bin/deCONZ -platform minimal --ws-port=8081";
      ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      Restart = "always";
      RestartSec = "10s";
      StartLimitInterval = "1min";
      User = "deconz";
    };
  };

  services.mosquitto = {
    enable = true;
    host = "0.0.0.0";
    users = {
      "rw" = {
        acl = [ "topic readwrite #" ];
        password = pkgs.secrets.mqtt-password;
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 1883 8081 ];
  networking.firewall.allowedUDPPorts = [ 1883 ];

  services.influxdb = {
    enable = true;
  };

  users.extraUsers."hass".extraGroups = [ "dialout" ];
  services.home-assistant = {
    enable = true;
    openFirewall = true;
    package = pkgs.home-assistant.override {
      extraPackages = ps: with ps; [ cryptography python-miio aiounifi PyChromecast ];
    };
    config = {
      homeassistant = {
        name = "Home";
        latitude = "51.28";
        longitude = "0.678";
        elevation = "20";
        unit_system = "metric";
        time_zone = "Europe/London";
        internal_url = "https://home.satanic.link";
        external_url = "https://home.satanic.link";
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
      mobile_app = { };
      frontend = { };
      history = { };
      config = { };
      deconz = {
        host = "127.0.0.1";
        port = "8080";
      };
      vacuum = {
        platform = "xiaomi_miio";
        host = "192.168.23.43";
        token = "30646a4c6259726d3834476862436553";
      };
      influxdb = { };
      mqtt = {
        broker = "127.0.0.1";
        username = "rw";
        password = pkgs.secrets.mqtt-password;
        discovery = true;
      };
      cover = [ ];
      esphome = {};
      media_player = [
        {
          platform = "kodi";
          host = "amlogic-s912";
        }
      ];
      system_health = { };
      sun = { };
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
      automation = [
        /* Open/Close blinds */
        {
          trigger = {
            platform = "numeric_state";
            entity_id = "sun.sun";
            value_template = "{{ state_attr('sun.sun', 'elevation') }}";
            below = -3.0;
          };
          action = [
            {
              service = "cover.close_cover";
              entity_id = "cover.main_blinds";
            }
            {
              service = "cover.close_cover";
              entity_id = "cover.side_blinds";
            }
          ];
        }
        {
          trigger = {
            platform = "numeric_state";
            entity_id = "sun.sun";
            value_template = "{{ state_attr('sun.sun', 'elevation') }}";
            above = -2.0;
          };
          action = [
            {
              service = "cover.open_cover";
              entity_id = "cover.main_blinds";
            }
            {
              service = "cover.open_cover";
              entity_id = "cover.side_blinds";
            }
          ];
        }

        /* Start wake-up playlist */
        /* {
          trigger = {
            platform = "time";
            at = "07:30:00";
          };
          action = [
            {
              service = "media_player.select_source";
              data = {
                entity_id = "media_player.spotify_1139118329";
                source = "Spotifyd@tvheadend";
              };
            }
            {
              service = "media_player.play_media";
              data = {
                entity_id = "media_player.spotify_1139118329";
                media_content_type = "playlist";
                media_content_id = "spotify:playlist:1QyZvdRFOEiCZykP43c9Ie";
              };
            }
            {
              service = "media_player.shuffle_set";
              data = {
                entity_id = "media_player.spotify_1139118329";
                shuffle = true;
              };
            }
            {
              service = "media_player.media_next_track";
              data = {
                entity_id = "media_player.spotify_1139118329";
              };
            }
          ];
        } */
      ];
    };
  };

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

}
