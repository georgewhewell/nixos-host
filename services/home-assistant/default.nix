{
  pkgs,
  lib,
  network,
  ...
}: let
  haDomain = network.publicFqdn "home";
  philipsSonicareBle = pkgs.buildHomeAssistantComponent rec {
    owner = "mtheli";
    domain = "philips_sonicare_ble";
    version = "0.11.3";

    src = pkgs.fetchFromGitHub {
      inherit owner;
      repo = "philips_sonicare_ble";
      tag = "v${version}";
      hash = "sha256-0Jx13b/F4JAcrauCZSagkbbNmQuT29ssIgXJmnpG4ac=";
    };

    nativeBuildInputs = [pkgs.python3];

    postPatch = ''
      python - <<'PY'
      import json
      from pathlib import Path

      manifest = Path("custom_components/philips_sonicare_ble/manifest.json")
      data = json.loads(manifest.read_text())
      data.pop("bluetooth", None)
      manifest.write_text(json.dumps(data, indent=2) + "\n")
      PY
    '';

    dependencies = with pkgs.home-assistant.python3Packages; [
      bleak
      bleak-retry-connector
      dbus-fast
      packaging
    ];

    meta = with lib; {
      description = "Local BLE Home Assistant integration for Philips Sonicare toothbrushes";
      homepage = "https://github.com/mtheli/philips_sonicare_ble";
      license = licenses.mit;
    };
  };

  # Not in nixpkgs - of the ~107 packaged custom components the only
  # 3D-printing one is elegoo_printer - so it is built from the upstream tag,
  # the same shape as philipsSonicareBle above. Talks MQTT over TLS to the
  # printer on :8883 for telemetry and control; the chamber camera is left to
  # go2rtc (services/go2rtc.nix) because this integration's camera option opens
  # a *permanent* connection to :6000 rather than one per viewer.
  bambuLab = pkgs.buildHomeAssistantComponent rec {
    owner = "greghesp";
    domain = "bambu_lab";
    version = "2.2.22";

    src = pkgs.fetchFromGitHub {
      inherit owner;
      repo = "ha-bambulab";
      tag = "v${version}";
      hash = "sha256-JRJ+tfllDuMrtz+5VQL2l5nkhJQXRoNvsvFnrReSZHE=";
    };

    # Upstream commits a placeholder version and only stamps the real one into
    # the manifest when its CI builds the release asset. The builder asserts
    # that the manifest version matches, so restore it from the tag.
    postPatch = ''
      substituteInPlace custom_components/bambu_lab/manifest.json \
        --replace-fail '"version": "0.0.0"' '"version": "${version}"'
    '';

    # beautifulsoup4 is the integration's only declared requirement; the rest
    # are imports that happen to be satisfied by home-assistant's own closure
    # and are named here so an upstream change cannot silently break them.
    #
    # cloudscraper and curl_cffi are deliberately absent. They exist only to
    # get past Cloudflare when logging in to Bambu Cloud, both imports are
    # already wrapped in try/except ImportError, and this printer is driven
    # entirely over the LAN.
    dependencies = with pkgs.home-assistant.python3Packages; [
      aiofiles
      beautifulsoup4
      packaging
      paho-mqtt
      pillow
      python-dateutil
    ];

    meta = with lib; {
      description = "Home Assistant integration for Bambu Lab printers";
      homepage = "https://github.com/greghesp/ha-bambulab";
      license = licenses.mit;
    };
  };
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

  # 8123 for internal networks only — never the WAN interface (external
  # access goes through the trex nginx proxy at ${haDomain}).
  networking.firewall.interfaces."br0.lan".allowedTCPPorts = [8123];
  networking.firewall.interfaces."br0.lan.50".allowedTCPPorts = [8123];
  networking.firewall.interfaces."wg-home".allowedTCPPorts = [8123];

  services.home-assistant = {
    enable = true;
    openFirewall = false;
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      advanced-camera-card
      auto-entities
    ];
    customComponents = with pkgs.home-assistant-custom-components;
      [
        frigate
        roborock_custom_map
        tuya_local
      ]
      ++ [philipsSonicareBle bambuLab];
    extraPackages = ps:
      with ps; [
        defusedxml
        isal
        zlib-ng
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
        ibeacon-ble
        kegtron-ble
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
