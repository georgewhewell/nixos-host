{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.esphome-dashboard;

  esphomeRoot = ../esphomes;
  allDevices = import "${esphomeRoot}/all-devices.nix" {inherit pkgs;};

  stateDir = "/var/lib/esphome";

  # Dedicated group used to let the DynamicUser `esphome` service read the
  # decrypted sops secrets that populate `secrets.yaml`.
  secretsGroup = "esphome-secrets";

  # Keys that the Nix-rendered device YAMLs reference via `!secret`.
  # Each key maps to one sops source file/key below.
  #   sops key in repo file  →  secrets.yaml key consumed by ESPHome
  secretKeys = [
    "api_key"
    "ota_key"
    "web_password"
    "wifi_ssid"
    "wifi_password"
  ];

  # Translate a secrets.yaml key to its sops source location.
  sopsSourceFor = key:
    if key == "wifi_password"
    then {
      file = ../secrets/wifi.yaml;
      sopsKey = "wifi-password-backup";
    }
    else {
      file = ../secrets/esphome.yaml;
      sopsKey = key;
    };

  secretName = key: "esphome-${lib.replaceStrings ["_"] ["-"] key}";
  secretPath = key: "/run/secrets/${secretName key}";

  # Rebuild /var/lib/esphome contents on every start so the nix-rendered
  # YAMLs stay authoritative. The sentinel `"@@SECRET:KEY@@"` written by
  # esphomes/lib.nix is rewritten here to a native `!secret KEY` tag so
  # the ESPHome YAML loader resolves values from secrets.yaml.
  # Build shell snippets that load each secret into a bash variable
  # (stripping the trailing newline that sops-nix writes) and then hand
  # them to `jq --arg`.
  loadSecretVars =
    lib.concatMapStringsSep "\n"
    (k: "    ${k}=\"$(<${secretPath k})\"")
    secretKeys;

  jqArgs =
    lib.concatMapStringsSep " \\\n        "
    (k: "--arg ${k} \"\$${k}\"")
    secretKeys;

  jqObject =
    "{"
    + lib.concatMapStringsSep ", " (k: "${k}: \$${k}") secretKeys
    + "}";

  prestart = pkgs.writeShellScript "esphome-dashboard-prestart" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath (with pkgs; [coreutils gnused jq findutils])}:$PATH

    state_dir="${stateDir}"
    yaml_src="${allDevices.yamlDir}"

    mkdir -p "$state_dir"

    # Wipe previous nix-managed device configs and symlinks, leaving
    # dashboard state (.esphome/, build artefacts) intact.
    find "$state_dir" -maxdepth 1 -type f -name '*.yaml' -delete
    find "$state_dir" -maxdepth 1 -type l -delete

    for src in "$yaml_src"/*.yaml; do
      name="$(basename "$src")"
      sed -E 's/[\x27"]?@@SECRET:([A-Za-z0-9_]+)@@[\x27"]?/!secret \1/g' \
        "$src" > "$state_dir/$name"
    done

    # External components referenced by some devices.
    ln -sfn ${esphomeRoot}/external-components "$state_dir/external-components"

    umask 077
${loadSecretVars}
    jq -n \
      ${jqArgs} \
      '${jqObject}' \
      > "$state_dir/secrets.yaml"
  '';
in {
  options.services.esphome-dashboard = {
    enable = lib.mkEnableOption "ESPHome dashboard preloaded with Nix-rendered device YAMLs";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the ESPHome dashboard TCP port on the firewall.";
    };

    address = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address for the ESPHome dashboard.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6052;
      description = "TCP port for the ESPHome dashboard.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${secretsGroup} = {};

    sops.secrets = lib.listToAttrs (
      map
      (key: let
        src = sopsSourceFor key;
      in {
        name = secretName key;
        value = {
          sopsFile = src.file;
          key = src.sopsKey;
          path = secretPath key;
          owner = "root";
          group = secretsGroup;
          mode = "0440";
        };
      })
      secretKeys
    );

    services.esphome = {
      enable = true;
      inherit (cfg) openFirewall address port;
    };

    systemd.services.esphome.serviceConfig = {
      # ESPHome 2026.8 removed its dashboard command. Keep the older command
      # on legacy package sets and use the separate Device Builder otherwise.
      ExecStart = lib.mkIf (lib.versionAtLeast config.services.esphome.package.version "2026.8") (
        lib.mkForce (lib.escapeShellArgs (
          [ (lib.getExe pkgs.esphome-device-builder) "--remote-build-host" cfg.address ]
          ++ (if config.services.esphome.enableUnixSocket then
            [ "--socket" "/run/esphome/esphome.sock" ]
          else
            [ "--host" cfg.address "--port" (toString cfg.port) ])
          ++ [ stateDir ]
        ))
      );
      ExecStartPre = ["${prestart}"];
      SupplementaryGroups = lib.mkForce ["dialout" secretsGroup];
      StateDirectoryMode = lib.mkForce "0700";
    };
  };
}
