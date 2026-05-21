{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.max-perf;
  mqttCfg = cfg.mqtt;
  hostName = config.networking.hostName;
  hostObjectId = lib.replaceStrings ["-"] ["_"] hostName;

  indexedWrites =
    builtins.genList
    (index: {
      inherit index;
      entry = builtins.elemAt cfg.writes index;
    })
    (builtins.length cfg.writes);

  mqttStateTopic = "${mqttCfg.topicPrefix}/hosts/${hostName}/state";
  mqttCommandTopic = "${mqttCfg.topicPrefix}/hosts/${hostName}/set";
  mqttGlobalCommandTopic = "${mqttCfg.topicPrefix}/all/set";
  mqttAvailabilityTopic = "${mqttCfg.topicPrefix}/hosts/${hostName}/availability";
  mqttDiscoveryTopic = "${mqttCfg.discoveryPrefix}/switch/max_perf_${hostObjectId}/config";

  mqttSwitchObjectId = "${hostObjectId}_max_performance";
  mqttDiscoveryPayload = builtins.toJSON {
    name = "${hostName} Max Performance";
    object_id = mqttSwitchObjectId;
    unique_id = "max-perf-${hostName}";
    icon = "mdi:fan";
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
      identifiers = ["host-${hostName}"];
      name = hostName;
      manufacturer = "NixOS";
      model = "Linux Host";
    };
  };

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
      if [ ! -r "$mqtt_pw_file" ]; then
        echo "max-perf-mqtt: password file not readable: $mqtt_pw_file" >&2
        return 1
      fi
      pw="$(${pkgs.coreutils}/bin/cat "$mqtt_pw_file")"
      exec_retain=()
      if [ "$retain_flag" = "retain" ]; then
        exec_retain=(-r)
      fi
      ${pkgs.mosquitto}/bin/mosquitto_pub \
        -h "$mqtt_host" \
        -p "$mqtt_port" \
        -u "$mqtt_user" \
        -P "$pw" \
        -q "$mqtt_qos" \
        "''${exec_retain[@]}" \
        -t "$topic" \
        -m "$payload"
    }
  '';

  startScript = pkgs.writeShellScript "max-perf-start" ''
    set -euo pipefail

    state_dir="/var/lib/max-perf"
    restore_script="$state_dir/restore.sh"
    success=0

    rollback() {
      if [ "$success" -eq 1 ]; then
        return 0
      fi

      ${lib.concatMapStrings ({
          index,
          entry,
        }: let
          idx = toString index;
          pathArg = lib.escapeShellArg entry.path;
        in ''
          if [ -f "$state_dir/${idx}.prev" ] && [ -e ${pathArg} ]; then
            cat "$state_dir/${idx}.prev" > ${pathArg} || true
          fi
        '')
        (lib.reverseList indexedWrites)}

      rm -f "$state_dir"/*.prev "$restore_script"
    }

    trap rollback EXIT

    mkdir -p "$state_dir"
    rm -f "$state_dir"/*.prev "$restore_script"
    touch "$restore_script"
    chmod 0700 "$restore_script"

    ${lib.concatMapStrings ({
        index,
        entry,
      }: let
        idx = toString index;
        pathArg = lib.escapeShellArg entry.path;
        valueArg = lib.escapeShellArg entry.value;
      in ''
        if [ ! -e ${pathArg} ]; then
          echo "max-perf: missing path ${entry.path}" >&2
          exit 1
        fi
        cat ${pathArg} > "$state_dir/${idx}.prev"
        printf '%s\n' ${valueArg} > ${pathArg}
      '')
      indexedWrites}

    export MAX_PERF_STATE_DIR="$state_dir"
    export MAX_PERF_RESTORE_SCRIPT="$restore_script"
    ${cfg.activeScript}

    success=1
    trap - EXIT
  '';

  stopScript = pkgs.writeShellScript "max-perf-stop" ''
    set -euo pipefail

    state_dir="/var/lib/max-perf"
    restore_script="$state_dir/restore.sh"

    ${lib.concatMapStrings ({
        index,
        entry,
      }: let
        idx = toString index;
        pathArg = lib.escapeShellArg entry.path;
      in ''
        if [ -f "$state_dir/${idx}.prev" ] && [ -e ${pathArg} ]; then
          cat "$state_dir/${idx}.prev" > ${pathArg}
        fi
      '')
      (lib.reverseList indexedWrites)}

    if [ -s "$restore_script" ]; then
      "${pkgs.runtimeShell}" "$restore_script"
    fi

    rm -f "$state_dir"/*.prev "$restore_script"
  '';

  mqttPublishStateScript = pkgs.writeShellScript "max-perf-mqtt-publish-state" ''
    set -euo pipefail
    ${mqttCommonShell}

    forced_state="''${1:-}"
    case "$forced_state" in
      ON|OFF)
        state="$forced_state"
        ;;
      "")
        active_state="$(${pkgs.systemd}/bin/systemctl show --property=ActiveState --value max-perf.service 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '\n')"
        case "$active_state" in
          active|activating|reloading)
            state="ON"
            ;;
          *)
            state="OFF"
            ;;
        esac
        ;;
      *)
        echo "usage: $0 [ON|OFF]" >&2
        exit 2
        ;;
    esac

    mqtt_pub ${lib.escapeShellArg mqttStateTopic} "$state" retain
  '';

  mqttPublishAvailabilityScript = pkgs.writeShellScript "max-perf-mqtt-publish-availability" ''
    set -euo pipefail
    ${mqttCommonShell}
    payload="''${1:-}"
    case "$payload" in
      online|offline) ;;
      *)
        echo "usage: $0 {online|offline}" >&2
        exit 2
        ;;
    esac
    mqtt_pub ${lib.escapeShellArg mqttAvailabilityTopic} "$payload" retain
  '';

  mqttPublishDiscoveryScript = pkgs.writeShellScript "max-perf-mqtt-publish-discovery" ''
    set -euo pipefail
    ${mqttCommonShell}
    mqtt_pub ${lib.escapeShellArg mqttDiscoveryTopic} ${lib.escapeShellArg mqttDiscoveryPayload} retain
  '';

  mqttAgentScript = pkgs.writeShellScript "max-perf-mqtt-agent" ''
    set -euo pipefail

    ${mqttCommonShell}

    publish_bootstrap() {
      ${mqttPublishDiscoveryScript} || true
      ${mqttPublishAvailabilityScript} online || true
      ${mqttPublishStateScript} || true
    }

    handle_payload() {
      local payload="$1"
      local normalized
      normalized="$(${pkgs.coreutils}/bin/printf '%s' "$payload" | ${pkgs.coreutils}/bin/tr '[:lower:]' '[:upper:]')"

      case "$normalized" in
        ON|1|TRUE)
          ${pkgs.systemd}/bin/systemctl start max-perf.service
          ;;
        OFF|0|FALSE)
          ${pkgs.systemd}/bin/systemctl stop max-perf.service
          ;;
        TOGGLE)
          if ${pkgs.systemd}/bin/systemctl -q is-active max-perf.service; then
            ${pkgs.systemd}/bin/systemctl stop max-perf.service
          else
            ${pkgs.systemd}/bin/systemctl start max-perf.service
          fi
          ;;
        STATUS)
          ${mqttPublishStateScript}
          ;;
        *)
          echo "max-perf-mqtt: ignoring payload '$payload'" >&2
          ;;
      esac
    }

    publish_bootstrap

    while true; do
      if [ ! -r "$mqtt_pw_file" ]; then
        echo "max-perf-mqtt: waiting for password file $mqtt_pw_file" >&2
        sleep 2
        continue
      fi
      pw="$(${pkgs.coreutils}/bin/cat "$mqtt_pw_file")"
      publish_bootstrap
      ${pkgs.mosquitto}/bin/mosquitto_sub \
        -h "$mqtt_host" \
        -p "$mqtt_port" \
        -u "$mqtt_user" \
        -P "$pw" \
        -q "$mqtt_qos" \
        -v \
        -t ${lib.escapeShellArg mqttGlobalCommandTopic} \
        -t ${lib.escapeShellArg mqttCommandTopic} |
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        topic="''${line%% *}"
        if [ "$line" = "$topic" ]; then
          payload=""
        else
          payload="''${line#* }"
        fi
        handle_payload "$payload"
      done || true

      sleep 2
      publish_bootstrap
    done
  '';

  cli = pkgs.writeShellScriptBin "max-perf" ''
    case "''${1:-}" in
      on|start)
        exec ${pkgs.systemd}/bin/systemctl start max-perf.service
        ;;
      off|stop)
        exec ${pkgs.systemd}/bin/systemctl stop max-perf.service
        ;;
      restart)
        exec ${pkgs.systemd}/bin/systemctl restart max-perf.service
        ;;
      status)
        if ${pkgs.systemd}/bin/systemctl -q is-active max-perf.service; then
          echo on
        else
          echo off
        fi
        ;;
      *)
        echo "usage: max-perf {on|off|start|stop|restart|status}" >&2
        exit 2
        ;;
    esac
  '';

  writeType = lib.types.submodule {
    options = {
      path = lib.mkOption {
        type = lib.types.str;
        description = "File/sysfs path to snapshot and write while max-perf is active.";
        example = "/sys/class/ec_su_axb35/fan1/level";
      };
      value = lib.mkOption {
        type = lib.types.str;
        description = "Value written to `path` while max-perf is active.";
        example = "5";
      };
    };
  };
in {
  options.services.max-perf = {
    enable = lib.mkEnableOption "per-host max-performance hooks";

    description = lib.mkOption {
      type = lib.types.str;
      default = "Host max-performance hooks";
      description = "Description for the generated systemd units.";
    };

    writes = lib.mkOption {
      type = lib.types.listOf writeType;
      default = [];
      description = ''
        Paths to snapshot on start and restore on stop, with the active values to apply
        while the `max-perf` service is active.
      '';
    };

    activeScript = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        # Optional extra actions after declarative writes are applied.
        # You may append custom restore commands to $MAX_PERF_RESTORE_SCRIPT.
        :
      '';
      description = ''
        Shell snippet run when max-performance mode is activated.
        Use `writes` for automatic snapshot/restore; this is for extra host-specific actions.
        If needed, append restore commands to `$MAX_PERF_RESTORE_SCRIPT`.
      '';
    };

    path = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Packages added to PATH for the max-perf service scripts and helper command.";
    };

    after = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional systemd ordering dependencies for the `max-perf` service.";
    };

    wants = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional systemd Wants= entries for the `max-perf` service.";
    };

    mqtt = {
      enable = lib.mkEnableOption "MQTT pull control and Home Assistant discovery for max-perf";

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "MQTT broker hostname/IP.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 1883;
        description = "MQTT broker port.";
      };

      username = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "MQTT username.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to a file containing the MQTT password.";
      };

      topicPrefix = lib.mkOption {
        type = lib.types.str;
        default = "home/max_perf";
        description = "Base topic prefix for max-perf control/state topics.";
      };

      discoveryPrefix = lib.mkOption {
        type = lib.types.str;
        default = "homeassistant";
        description = "Home Assistant MQTT discovery prefix.";
      };

      qos = lib.mkOption {
        type = lib.types.ints.between 0 2;
        default = 1;
        description = "MQTT QoS for publish/subscribe operations.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.writes != []) || (lib.strings.trim cfg.activeScript != "");
        message = "services.max-perf requires either non-empty `writes` or `activeScript`";
      }
      {
        assertion = (!mqttCfg.enable) || (mqttCfg.username != null && mqttCfg.passwordFile != null);
        message = "services.max-perf.mqtt requires `username` and `passwordFile` when enabled";
      }
    ];

    environment.systemPackages = [cli];

    systemd.tmpfiles.rules = [
      "d /var/lib/max-perf 0755 root root -"
    ];

    systemd.services.max-perf = {
      description = cfg.description;
      wantedBy = [];
      after = cfg.after;
      wants = cfg.wants;
      serviceConfig =
        {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = startScript;
          ExecStop = stopScript;
        }
        // lib.optionalAttrs mqttCfg.enable {
          ExecStartPost = ["-${mqttPublishStateScript} ON"];
          ExecStopPost = ["-${mqttPublishStateScript} OFF"];
        };
      path = cfg.path ++ lib.optionals mqttCfg.enable [pkgs.mosquitto pkgs.coreutils];
    };

    systemd.services.max-perf-mqtt = lib.mkIf mqttCfg.enable {
      description = "MQTT control/discovery agent for max-perf";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "2s";
        ExecStart = mqttAgentScript;
        ExecStopPost = [ "-${mqttPublishAvailabilityScript} offline" ];
      };
      path = [pkgs.mosquitto pkgs.coreutils pkgs.systemd];
    };
  };
}
