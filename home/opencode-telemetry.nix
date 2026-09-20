{ config, lib, pkgs, ... }:
let
  cfg = config.programs.opencode.telemetry;
  # API-only packages join OpenCode's native SDK/context registry. They do
  # not install another tracer, span processor, logger or exporter.
  otelApi = pkgs.stdenvNoCC.mkDerivation {
    pname = "opencode-otel-api";
    version = "1.9.0";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@opentelemetry/api/-/api-1.9.0.tgz";
      hash = "sha256-GaMyG/uHtKskUyIzxgFJFqPHEa8HGVnZFH3fltij2os=";
    };
    dontBuild = true;
    installPhase = ''
      mkdir -p "$out"
      cp -r build package.json "$out/"
    '';
  };
  otelCore = pkgs.stdenvNoCC.mkDerivation {
    pname = "opencode-otel-core";
    version = "2.11.0";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@opentelemetry/core/-/core-2.11.0.tgz";
      hash = "sha256-AI/qWNKh31rEgbrPM1MnP8vuG/l66aLnS5QK0AC+88E=";
    };
    dontBuild = true;
    installPhase = ''
      mkdir -p "$out/node_modules/@opentelemetry"
      cp -r build package.json "$out/"
      ln -s ${otelApi} "$out/node_modules/@opentelemetry/api"
    '';
  };
in {
  options.programs.opencode = {
    telemetry = {
      enable = lib.mkEnableOption "OpenCode's native OpenTelemetry and Hellas W3C propagation";
      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:4318";
        description = "OTLP HTTP collector base URL. Use a trusted local collector that removes prompt, tool-result and header attributes before exporting traces.";
      };
    };
    # Applying this to the standard package option keeps interactive commands
    # and system services on the same executable, even in an older tmux shell.
    package = lib.mkOption { apply = package:
      if !cfg.enable || package == null then package else pkgs.symlinkJoin {
        name = "${lib.getName package}-otel-${lib.getVersion package}";
        paths = [ package ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram "$out/bin/opencode" \
            --set-default OTEL_EXPORTER_OTLP_ENDPOINT ${lib.escapeShellArg cfg.endpoint}
        '';
        inherit (package) meta;
      }; };
  };
  config = lib.mkIf cfg.enable {
    programs.opencode.settings.experimental.openTelemetry = true;
    xdg.configFile."opencode/plugins/hellas-tracing.js".source =
      pkgs.replaceVars ./opencode-tracing.js { inherit otelApi otelCore; };
  };
}
