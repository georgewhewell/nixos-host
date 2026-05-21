{
  pkgs,
  lib,
  network,
  ...
}: let
  haDomain = network.publicFqdn "home";
in {
  imports = [
    ./lights.nix
    ./lovelace.nix
    ./max-perf.nix
    ./mqtt.nix
    ./xmrig.nix
    ./vacuum.nix
    ./homekit.nix
  ];

  environment.systemPackages = with pkgs; [
    home-assistant-cli
    home-assistant-cli-go
  ];

  users.extraUsers."hass".extraGroups = ["dialout" "lp"];

  services.dbus.implementation = "broker";

  # services.esphome = {
  #   enable = true;
  #   address = "192.168.23.254"; # Linux TAP interface (VPP BVI .1 is not on Linux)
  #   openFirewall = true;
  # };

  # Fix platformio permissions issue with DynamicUser
  # systemd.services.esphome = {
  #   serviceConfig = {
  #     # Override DynamicUser to use a static user
  #     DynamicUser = lib.mkForce false;
  #     # Ensure proper permissions for platformio cache
  #     StateDirectoryMode = lib.mkForce "0755";
  #     # Disable some hardening that interferes with platformio
  #     ProtectSystem = lib.mkForce false;
  #     PrivateUsers = lib.mkForce false;
  #   };
  #   preStart = ''
  #     # Ensure all esphome directories have correct permissions
  #     chown -R esphome:esphome /var/lib/esphome
  #     chmod -R u+rwX /var/lib/esphome
  #   '';
  # };

  # Create static esphome user
  # users.users.esphome = {
  #   isSystemUser = true;
  #   group = "esphome";
  #   home = "/var/lib/esphome";
  #   extraGroups = ["dialout"];
  # };
  # users.groups.esphome = {};

  services.home-assistant = {
    enable = true;
    openFirewall = true;
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      advanced-camera-card
      auto-entities
    ];
    customComponents = with pkgs.home-assistant-custom-components; [
      frigate
      roborock_custom_map
      tuya_local
    ];
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
        aiohttp-sse
        aioapcaccess
        aionut
        mcp
      ];
    config = {
      homeassistant = {
        name = "Home";
        country = "CH";
        # latitude = pkgs.secrets.home-lat;
        # longitude = pkgs.secrets.home-lng;
        elevation = "400";
        unit_system = "metric";
        time_zone = "Europe/Zurich";
        internal_url = "https://${haDomain}";
        external_url = "https://${haDomain}";
      };
      http = {
        server_host = network.routerIp;
        server_port = 8123;
        use_x_forwarded_for = true;
        trusted_proxies = [(network.primaryIp network.hosts.trex)];
      };
      mobile_app = {};
      frontend = {};
      lovelace = {
        mode = "storage";
        resource_mode = "yaml";
        dashboards = {
          lovelace = {
            mode = "yaml";
            filename = "ui-lovelace.yaml";
            title = "Overview";
            icon = "mdi:view-dashboard";
            show_in_sidebar = true;
          };
        };
      };
      input_boolean = {
        max_perf_all = {
          name = "Max Performance (All)";
          icon = "mdi:fan";
        };
        xmrig_all = {
          name = "XMRig (All)";
          icon = "mdi:pickaxe";
        };
      };
      frigate = {};
      go2rtc = {
        url = "http://localhost:1984";
      };
      history = {};
      config = {};
      zha = {};
      system_health = {};
      api = {};
      websocket_api = {};
      cli = {};
      prometheus = {};
    };
  };
}
