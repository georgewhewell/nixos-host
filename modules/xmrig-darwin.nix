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
      default = network.primaryIp network.hosts.trex;
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

  config = lib.mkIf (pkgs.stdenv.hostPlatform.isDarwin && cfg.enable) (let
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

    # Prometheus exporter for darwin: the linux miners expose xmrig metrics via
    # mtail parsing journald, but macOS has no journald/mtail. Translate xmrig's
    # local HTTP API to the same xmrig_* metrics on :3903 so trex's VM scrapes
    # the Macs identically (same metric names, so existing dashboards just work).
    xmrigExporterPython = pkgs.writeTextFile {
      name = "xmrig-exporter";
      destination = "/bin/xmrig-exporter";
      executable = true;
      text = ''
        #!${pkgs.python3}/bin/python3
        import json
        import urllib.request
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

        API = "http://${cfg.httpApi.host}:${toString cfg.httpApi.port}/2/summary"
        TOKEN = "${cfg.httpApi.accessToken}"
        PORT = 3903  # match the linux mtail xmrig exporter port


        def render():
            out = []

            def emit(name, value, typ="gauge"):
                out.append(f"# TYPE {name} {typ}")
                out.append(f"{name} {value}")

            try:
                req = urllib.request.Request(
                    API, headers={"Authorization": f"Bearer {TOKEN}"}
                )
                with urllib.request.urlopen(req, timeout=4) as resp:
                    d = json.load(resp)
            except Exception:
                emit("xmrig_up", 0)
                return "\n".join(out) + "\n"

            def num(x):
                return x if isinstance(x, (int, float)) else 0

            hr = d.get("hashrate", {}).get("total") or [0, 0, 0]
            emit("xmrig_hashrate_10s", num(hr[0] if len(hr) > 0 else 0))
            emit("xmrig_hashrate_60s", num(hr[1] if len(hr) > 1 else 0))
            emit("xmrig_hashrate_15m", num(hr[2] if len(hr) > 2 else 0))
            emit("xmrig_hashrate_max", num(d.get("hashrate", {}).get("highest")))
            res = d.get("results", {})
            good = num(res.get("shares_good"))
            total = num(res.get("shares_total"))
            emit("xmrig_shares_accepted_total", int(good), "counter")
            emit("xmrig_shares_rejected_total", int(max(0, total - good)), "counter")
            emit("xmrig_difficulty_current", num(res.get("diff_current")))
            emit("xmrig_paused", 1 if d.get("paused") else 0)
            emit("xmrig_up", 1)
            return "\n".join(out) + "\n"


        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path.split("?")[0] != "/metrics":
                    self.send_response(404)
                    self.end_headers()
                    return
                body = render().encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; version=0.0.4")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *a):
                pass


        ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
      '';
    };
  in {
    sconfig.xmrig.mqttSwitch.enable = lib.mkDefault (mqttCfg.passwordFile != null);

    assertions = [
      {
        assertion = (!mqttCfg.enable) || (mqttCfg.username != null && mqttCfg.passwordFile != null);
        message = "sconfig.xmrig.mqttSwitch requires `username` and `passwordFile` when enabled";
      }
    ];

    environment.systemPackages = [cfg.package];

    # Run as system daemons (root), NOT per-user GUI agents. macOS 15+/26 Local
    # Network Privacy (TCC) blocks user-session processes from reaching LAN
    # addresses until the user clicks an "allow local network" prompt — which is
    # impossible on a headless build slave and silently dropped xmrig's pool SYN
    # before it hit any interface. System daemons are exempt from that prompt, so
    # this lets the miner reach the p2pool host on the LAN without any GUI grant.
    launchd.daemons.xmrig = {
      path = [cfg.package];
      command = "${xmrigRunScript}";
      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/xmrig.out.log";
        StandardErrorPath = "/tmp/xmrig.err.log";
      };
    };

    launchd.daemons.xmrig-mqtt = lib.mkIf agentEnabled {
      path = [pkgs.curl pkgs.coreutils];
      command = "${xmrigMqttAgentPython}/bin/xmrig-mqtt-agent";
      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/xmrig-mqtt.out.log";
        StandardErrorPath = "/tmp/xmrig-mqtt.err.log";
      };
    };

    # Prometheus exporter (xmrig HTTP API -> :3903) so trex's VictoriaMetrics
    # collects hashrate/shares from the Macs like the linux mtail miners.
    launchd.daemons.xmrig-exporter = lib.mkIf cfg.httpApi.enable {
      command = "${xmrigExporterPython}/bin/xmrig-exporter";
      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/xmrig-exporter.out.log";
        StandardErrorPath = "/tmp/xmrig-exporter.err.log";
      };
    };
  });
}
