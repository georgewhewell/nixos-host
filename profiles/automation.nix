{ config, pkgs, ...}:

{

  # BT audio passthu
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  users.users.pulse.extraGroups = [ "lp" ];

  hardware.pulseaudio = {
    enable = true;
    extraModules = [ pkgs.pulseaudio-modules-bt ];
    support32Bit = true;
    systemWide = true;
    extraConfig = ''
      # make bluetooth work?
      load-module module-bluetooth-policy
      load-module module-bluetooth-discover
    '';
  };

  systemd.services.spotifyd = {
    description = "spotifyd client";
    after = [ "network.target" ];
    wantedBy = ["multi-user.target"];
    serviceConfig.ExecStart = ''
      ${pkgs.spotifyd}/bin/spotifyd --username 1139118329 --password Oojae0ash2sh --device-name "UE Mobile Boombox"
    '';
  };

  systemd.services.am43-ctrl = {
    description = "blind controller";
    after = [ "network.target" ];
    wantedBy = ["multi-user.target"];
    serviceConfig.ExecStart = ''
      ${pkgs.am43-ctrl}/bin/am43ctrl --mqtt-url mqtt://rw:thepassword@nixhost.lan 02:c4:da:36:73:79 02:be:75:37:b6:0a
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
        password = "thepassword";
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
    # configWritable = true;
    package = pkgs.home-assistant.override {
      extraPackages = ps: with ps; [ cryptography hass-nabucasa ];
    };
    config = {
      homeassistant = {
        name = "Home";
      	latitude = "51.28";
      	longitude = "0.678";
      	elevation = "20";
      	unit_system = "metric";
      	time_zone = "Europe/London";
      };
      http = {
        server_host = "0.0.0.0";
        server_port = 8123;
        base_url = "https://home.satanic.link";
        use_x_forwarded_for = true;
        trusted_proxies = [ "127.0.0.1" ];
      };
      mobile_app = {};
      frontend = {};
      history = {};
      config = {};
      deconz = {
        host = "127.0.0.1";
        port = "8080";
      };
      influxdb = {};
      mqtt = {
        broker = "nixhost.lan";
        username = "rw";
        password = "thepassword";
        discovery = true;
      };
      cover = [];
      esphome = {};
      media_player = [];
      system_health = {};
      sun = {};
      plant =
          let mkPlant = name: {
           sensors = {
             moisture = "sensor.${name}_moisture";
             battery = "sensor.${name}_battery";
             temperature = "sensor.${name}_temperature";
             conductivity = "sensor.${name}_conductivity";
             brightness = "sensor.${name}_light";
           };
      }; in {
        poppies = mkPlant "poppies";
        strawberries = mkPlant "strawberries";
        nectarine = mkPlant "nectarine";
        lettuce = mkPlant "lettuce";
      };
      automation = [
        {
          trigger = {
            platform = "numeric_state";
            entity_id = "sun.sun";
            value_template = "{{ state_attr('sun.sun', 'elevation') }}";
            below = -3.0;
          };
          action = [{
           service = "cover.close_cover";
           entity_id = "cover.main_blinds";
          } {
            service = "cover.close_cover";
            entity_id = "cover.side_blinds";
          }];
        }
        {
          trigger = {
            platform = "numeric_state";
            entity_id = "sun.sun";
            value_template = "{{ state_attr('sun.sun', 'elevation') }}";
            above = -2.0;
          };
          action = [{
           service = "cover.open_cover";
           entity_id = "cover.main_blinds";
          } {
            service = "cover.open_cover";
            entity_id = "cover.side_blinds";
          }];
        }
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
