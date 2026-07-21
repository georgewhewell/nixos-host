{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.services.curve-optimizer;
  mqttCfg = cfg.mqtt;
  hostName = config.networking.hostName;
  hostObjectId = lib.replaceStrings [ "-" ] [ "_" ] hostName;
  neutralValue = 1048576;
  encodedValue = neutralValue + cfg.offset;
  ryzenadj = "${pkgs.ryzenadj}/bin/ryzenadj";

  mqttStateTopic = "${mqttCfg.topicPrefix}/hosts/${hostName}/state";
  mqttCommandTopic = "${mqttCfg.topicPrefix}/hosts/${hostName}/set";
  mqttAvailabilityTopic = "${mqttCfg.topicPrefix}/hosts/${hostName}/availability";
  mqttDiscoveryTopic = "${mqttCfg.discoveryPrefix}/switch/curve_optimizer_${hostObjectId}/config";

  mqttDiscoveryPayload = builtins.toJSON {
    name = "${hostName} Curve Optimizer";
    object_id = "${hostObjectId}_curve_optimizer";
    unique_id = "curve-optimizer-${hostName}";
    icon = "mdi:sine-wave";
    command_topic = mqttCommandTopic;
    state_topic = mqttStateTopic;
    availability_topic = mqttAvailabilityTopic;
    payload_on = "ON";
    payload_off = "OFF";
    state_on = "ON";
    state_off = "OFF";
    payload_available = "online";
    payload_not_available = "offline";
    device = {
      identifiers = [ "host-${hostName}" ];
      name = hostName;
      manufacturer = "NixOS";
      model = "Linux Host";
    };
  };

  applyScript = pkgs.writeShellScript "curve-optimizer-apply" ''
    set -euo pipefail
    echo "Applying Curve Optimizer ${toString cfg.offset} (encoded ${toString encodedValue})"
    exec ${ryzenadj} --set-coall=${toString encodedValue}
  '';

  resetScript = pkgs.writeShellScript "curve-optimizer-reset" ''
    set -euo pipefail
    echo "Resetting Curve Optimizer to neutral (encoded ${toString neutralValue})"
    exec ${ryzenadj} --set-coall=${toString neutralValue}
  '';

  mqttCommonShell = ''
    mqtt_host=${lib.escapeShellArg mqttCfg.host}
    mqtt_port=${lib.escapeShellArg (toString mqttCfg.port)}
    mqtt_user=${lib.escapeShellArg mqttCfg.username}
    mqtt_pw_file=${lib.escapeShellArg (toString mqttCfg.passwordFile)}
    mqtt_qos=${lib.escapeShellArg (toString mqttCfg.qos)}

    mqtt_pub() {
      local topic="$1"
      local payload="$2"
      local retain_flag="''${3:-}"
      local pw
      local -a retain_args=()
      if [ ! -r "$mqtt_pw_file" ]; then
        echo "curve-optimizer-mqtt: password file not readable: $mqtt_pw_file" >&2
        return 1
      fi
      pw="$(${pkgs.coreutils}/bin/cat "$mqtt_pw_file")"
      if [ "$retain_flag" = retain ]; then
        retain_args=(-r)
      fi
      ${pkgs.mosquitto}/bin/mosquitto_pub \
        -h "$mqtt_host" \
        -p "$mqtt_port" \
        -u "$mqtt_user" \
        -P "$pw" \
        -q "$mqtt_qos" \
        "''${retain_args[@]}" \
        -t "$topic" \
        -m "$payload"
    }
  '';

  publishStateScript = pkgs.writeShellScript "curve-optimizer-publish-state" ''
    set -euo pipefail
    ${mqttCommonShell}
    forced_state="''${1:-}"
    case "$forced_state" in
      ON|OFF) state="$forced_state" ;;
      "")
        active_state="$(${pkgs.systemd}/bin/systemctl show --property=ActiveState --value curve-optimizer.service 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '\n')"
        case "$active_state" in
          active|activating|reloading) state=ON ;;
          *) state=OFF ;;
        esac
        ;;
      *)
        echo "usage: $0 [ON|OFF]" >&2
        exit 2
        ;;
    esac
    mqtt_pub ${lib.escapeShellArg mqttStateTopic} "$state" retain
  '';

  publishAvailabilityScript = pkgs.writeShellScript "curve-optimizer-publish-availability" ''
    set -euo pipefail
    ${mqttCommonShell}
    case "''${1:-}" in
      online|offline) mqtt_pub ${lib.escapeShellArg mqttAvailabilityTopic} "$1" retain ;;
      *) echo "usage: $0 {online|offline}" >&2; exit 2 ;;
    esac
  '';

  publishDiscoveryScript = pkgs.writeShellScript "curve-optimizer-publish-discovery" ''
    set -euo pipefail
    ${mqttCommonShell}
    mqtt_pub ${lib.escapeShellArg mqttDiscoveryTopic} ${lib.escapeShellArg mqttDiscoveryPayload} retain
  '';

  mqttAgentScript = pkgs.writeShellScript "curve-optimizer-mqtt-agent" ''
    set -euo pipefail
    ${mqttCommonShell}

    publish_bootstrap() {
      ${publishDiscoveryScript} || true
      ${publishAvailabilityScript} online || true
      ${publishStateScript} || true
    }

    publish_bootstrap
    while true; do
      if [ ! -r "$mqtt_pw_file" ]; then
        echo "curve-optimizer-mqtt: waiting for $mqtt_pw_file" >&2
        sleep 2
        continue
      fi
      pw="$(${pkgs.coreutils}/bin/cat "$mqtt_pw_file")"
      ${pkgs.mosquitto}/bin/mosquitto_sub \
        -h "$mqtt_host" \
        -p "$mqtt_port" \
        -u "$mqtt_user" \
        -P "$pw" \
        -q "$mqtt_qos" \
        -t ${lib.escapeShellArg mqttCommandTopic} |
      while IFS= read -r payload; do
        normalized="$(${pkgs.coreutils}/bin/printf '%s' "$payload" | ${pkgs.coreutils}/bin/tr '[:lower:]' '[:upper:]')"
        case "$normalized" in
          ON|1|TRUE) ${pkgs.systemd}/bin/systemctl start curve-optimizer.service ;;
          OFF|0|FALSE) ${pkgs.systemd}/bin/systemctl stop curve-optimizer.service ;;
          TOGGLE)
            if ${pkgs.systemd}/bin/systemctl -q is-active curve-optimizer.service; then
              ${pkgs.systemd}/bin/systemctl stop curve-optimizer.service
            else
              ${pkgs.systemd}/bin/systemctl start curve-optimizer.service
            fi
            ;;
          STATUS) ${publishStateScript} ;;
          *) echo "curve-optimizer-mqtt: ignoring payload '$payload'" >&2 ;;
        esac
      done || true
      sleep 2
      publish_bootstrap
    done
  '';

  cli = pkgs.writeShellScriptBin "curve-optimizer" ''
    case "''${1:-}" in
      on|start) exec ${pkgs.systemd}/bin/systemctl start curve-optimizer.service ;;
      off|stop) exec ${pkgs.systemd}/bin/systemctl stop curve-optimizer.service ;;
      restart) exec ${pkgs.systemd}/bin/systemctl restart curve-optimizer.service ;;
      status)
        if ${pkgs.systemd}/bin/systemctl -q is-active curve-optimizer.service; then
          echo on
        else
          echo off
        fi
        ;;
      *) echo "usage: curve-optimizer {on|off|start|stop|restart|status}" >&2; exit 2 ;;
    esac
  '';
in
{
  options.services.curve-optimizer = {
    enable = lib.mkEnableOption "switchable Ryzen all-core Curve Optimizer";

    offset = lib.mkOption {
      type = lib.types.ints.between (-50) 30;
      default = -10;
      description = "All-core Curve Optimizer offset used while the service is active.";
    };

    mqtt = {
      enable = lib.mkEnableOption "MQTT and Home Assistant control for Curve Optimizer";
      host = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
      port = lib.mkOption { type = lib.types.port; default = 1883; };
      username = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
      passwordFile = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; };
      topicPrefix = lib.mkOption { type = lib.types.str; default = "home/curve_optimizer"; };
      discoveryPrefix = lib.mkOption { type = lib.types.str; default = "homeassistant"; };
      qos = lib.mkOption { type = lib.types.ints.between 0 2; default = 1; };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = (!mqttCfg.enable) || (mqttCfg.username != null && mqttCfg.passwordFile != null);
      message = "services.curve-optimizer.mqtt requires username and passwordFile";
    }];

    environment.systemPackages = [ cli ];

    systemd.services.curve-optimizer = {
      description = "Apply switchable Ryzen Curve Optimizer offset ${toString cfg.offset}";
      after = [ "ryzenadj.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = applyScript;
        ExecStop = resetScript;
      } // lib.optionalAttrs mqttCfg.enable {
        ExecStartPost = [ "-${publishStateScript} ON" ];
        ExecStopPost = [ "-${publishStateScript} OFF" ];
      };
    };

    systemd.services.curve-optimizer-mqtt = lib.mkIf mqttCfg.enable {
      description = "MQTT control and discovery for Ryzen Curve Optimizer";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "2s";
        ExecStart = mqttAgentScript;
        ExecStopPost = [ "-${publishAvailabilityScript} offline" ];
      };
      path = [ pkgs.mosquitto pkgs.coreutils pkgs.systemd ];
    };
  };
}
