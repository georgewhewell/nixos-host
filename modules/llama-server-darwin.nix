{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.sconfig.llama-server;
in {
  options.sconfig.llama-server = {
    enable = lib.mkEnableOption "Run llama.cpp's llama-server on Darwin via a launchd daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-cpp-latest;
      description = ''
        llama.cpp package. Defaults to the overlay's `llama-cpp-latest`, which is
        newer than nixpkgs' pin: Muse-Glimmer support only landed upstream on
        2026-08-10 (ggml-org/llama.cpp#26841), so nixpkgs' b9925 rejects the
        model outright with "unknown model architecture: 'muse-glimmer'".
      '';
    };

    # These are strings, deliberately, not `types.path`: a bare path literal
    # would copy a 56 GiB GGUF into the nix store on every evaluation. The
    # weights live on the target's filesystem and are referenced by name only.
    modelPath = lib.mkOption {
      type = lib.types.str;
      description = ''
        Path to the GGUF to serve. For a multi-shard model point this at the
        first shard; llama.cpp loads the siblings automatically.
      '';
    };

    alias = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Model name reported over the OpenAI-compatible API.";
    };

    mmprojPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Multimodal projector GGUF, enabling image input. Null disables vision.";
    };

    draftModelPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Draft model for speculative decoding (for Muse-Glimmer, the DFlash
        sidecar). Null disables speculative decoding.
      '';
    };

    contextSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 131072;
      description = "Context window in tokens. Shared across all slots.";
    };

    gpuLayers = lib.mkOption {
      type = lib.types.str;
      default = "all";
      description = "Layers to offload to Metal. `all`, `auto`, or an exact count.";
    };

    flashAttention = lib.mkOption {
      type = lib.types.enum ["on" "off" "auto"];
      default = "on";
      description = "Flash Attention mode passed to `-fa`.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Bind address. 0.0.0.0 exposes the server to the LAN.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "HTTP port for the OpenAI-compatible API, WebUI and /metrics.";
    };

    metrics = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose a Prometheus /metrics endpoint on the same port.";
    };

    jinja = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use the GGUF's Jinja chat template; required for tool calling.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["--spec-draft-n-max" "8"];
      description = "Additional flags appended to the llama-server invocation.";
    };
  };

  config = lib.mkIf (pkgs.stdenv.hostPlatform.isDarwin && cfg.enable) (let
    flags =
      [
        "--model"
        (toString cfg.modelPath)
        "--alias"
        cfg.alias
        "--ctx-size"
        (toString cfg.contextSize)
        "--n-gpu-layers"
        cfg.gpuLayers
        "--flash-attn"
        cfg.flashAttention
        "--host"
        cfg.host
        "--port"
        (toString cfg.port)
      ]
      ++ lib.optionals (cfg.mmprojPath != null) ["--mmproj" (toString cfg.mmprojPath)]
      ++ lib.optionals (cfg.draftModelPath != null) ["--spec-draft-model" (toString cfg.draftModelPath)]
      ++ lib.optional cfg.metrics "--metrics"
      ++ lib.optional cfg.jinja "--jinja"
      ++ cfg.extraFlags;

    runScript = pkgs.writeShellScript "llama-server-run" ''
      exec ${cfg.package}/bin/llama-server ${lib.escapeShellArgs flags}
    '';
  in {
    environment.systemPackages = [cfg.package];

    # Run as a system daemon (root), NOT a per-user GUI agent — same reasoning as
    # sconfig.xmrig on Darwin: macOS Local Network Privacy (TCC) blocks
    # user-session processes from LAN traffic until someone clicks an "allow
    # local network" prompt, which never happens on a headless box. System
    # daemons are exempt, so binding 0.0.0.0 actually serves the fleet.
    launchd.daemons.llama-server = {
      path = [cfg.package];
      command = "${runScript}";
      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;
        # A 56 GiB BF16 model takes a while to page in from disk on a cold
        # start; don't let launchd treat the slow first load as a crash loop.
        ThrottleInterval = 60;
        StandardOutPath = "/var/log/llama-server.out.log";
        StandardErrorPath = "/var/log/llama-server.err.log";
      };
    };
  });
}
