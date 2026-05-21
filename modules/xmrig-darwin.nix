{
  config,
  pkgs,
  lib,
  network,
  ...
}: let
  common = import ../lib/xmrig.nix { inherit lib network; };
  cfg = config.sconfig.xmrig;
in {
  options.sconfig.xmrig = {
    enable = lib.mkEnableOption "Run XMRig miner on Darwin via launchd user agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.xmrig;
      description = "XMRig package for Darwin.";
    };

    poolHost = lib.mkOption {
      type = lib.types.str;
      default = network.routerIp;
      description = "P2Pool/stratum host.";
    };

    poolPort = lib.mkOption {
      type = lib.types.port;
      default = 3333;
      description = "P2Pool/stratum port.";
    };

    rigId = lib.mkOption {
      type = lib.types.str;
      default = lib.attrByPath ["networking" "hostName"] "darwin" config;
      description = "Rig identifier used for XMRig pool user/pass.";
    };

    httpApi = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable XMRig HTTP API (required for inhibit/MQTT control).";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "XMRig HTTP API bind address.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8082;
        description = "XMRig HTTP API port.";
      };

      accessToken = lib.mkOption {
        type = lib.types.str;
        default = let host = lib.attrByPath ["networking" "hostName"] "darwin" config; in "xmrig-${host}-local";
        description = "XMRig HTTP API bearer token.";
      };
    };

    mqttSwitch = common.mqttSwitchOptions;

    inhibit = {
      nixBuilds = {
        enable = lib.mkEnableOption "Pause xmrig while local nix client processes are active";
      };
    };
  };

  config = lib.mkIf (pkgs.stdenv.isDarwin && cfg.enable) (let
    hostName = let
      hn = lib.attrByPath ["networking" "hostName"] null config;
    in if hn != null then hn else cfg.rigId;
    mqttCfg = cfg.mqttSwitch;
    agentEnabled = mqttCfg.enable || cfg.inhibit.nixBuilds.enable;

    xmrigConfigJson = builtins.toJSON ({
      autosave = false;
      "donate-level" = 0;
      cpu = {
        enabled = true;
        priority = 1;
      };
      opencl = false;
      cuda = false;
      pools = [
        {
          url = "${cfg.poolHost}:${toString cfg.poolPort}";
          user = cfg.rigId;
          pass = cfg.rigId;
          keepalive = true;
        }
      ];
    }
    // lib.optionalAttrs cfg.httpApi.enable {
      http = {
        enabled = true;
        host = cfg.httpApi.host;
        port = cfg.httpApi.port;
        restricted = false;
        "access-token" = cfg.httpApi.accessToken;
      };
    });

    xmrigConfigFile = pkgs.writeText "xmrig-darwin-config.json" xmrigConfigJson;

    xmrigRunScript = pkgs.writeShellScript "xmrig-darwin-run" ''
      exec ${cfg.package}/bin/xmrig --config ${xmrigConfigFile}
    '';

    # MQTT config (shared with Linux via common library)
    topics = common.mkMqttTopics { inherit mqttCfg hostName; };
    payloads = common.mkDiscoveryPayloads {
      inherit hostName topics;
      platformModel = "macOS Host";
    };
    mqttAgentConfig = common.mkMqttAgentConfig { inherit mqttCfg topics payloads; };

    agentConfigJson = builtins.toJSON {
      platform = "darwin";
      mqtt = mqttAgentConfig;
      xmrigApi = {
        baseUrl = "http://${cfg.httpApi.host}:${toString cfg.httpApi.port}";
        token = cfg.httpApi.accessToken;
      };
      inhibitor = {
        nixBuilds = {
          enable = cfg.inhibit.nixBuilds.enable;
        };
      };
      system = {
        launchdLabel = "org.nixos.xmrig";
      };
    };

    xmrigMqttAgentPython = common.mkMqttAgentPython { inherit pkgs agentConfigJson; };
  in {
    sconfig.xmrig.mqttSwitch.enable = lib.mkDefault (mqttCfg.passwordFile != null);

    assertions = [
      {
        assertion = (!mqttCfg.enable) || (mqttCfg.username != null && mqttCfg.passwordFile != null);
        message = "sconfig.xmrig.mqttSwitch requires `username` and `passwordFile` when enabled";
      }
    ];

    environment.systemPackages = [cfg.package];

    launchd.user.agents.xmrig = {
      path = [cfg.package];
      command = "${xmrigRunScript}";
      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/xmrig.out.log";
        StandardErrorPath = "/tmp/xmrig.err.log";
      };
    };

    launchd.user.agents.xmrig-mqtt = lib.mkIf agentEnabled {
      path = [pkgs.curl pkgs.coreutils];
      command = "${xmrigMqttAgentPython}/bin/xmrig-mqtt-agent";
      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/xmrig-mqtt.out.log";
        StandardErrorPath = "/tmp/xmrig-mqtt.err.log";
      };
    };
  });
}
