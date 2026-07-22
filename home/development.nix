{ config
, lib
, pkgs
, inputs
, ...
}:
let
  grokPackage = inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.grok;
  grokWithPrivateOtel = pkgs.symlinkJoin {
    name = "grok-private-otel";
    paths = [ grokPackage ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/grok \
        --set GROK_EXTERNAL_OTEL "1" \
        --set OTEL_METRICS_EXPORTER "otlp" \
        --set OTEL_LOGS_EXPORTER "otlp" \
        --set OTEL_EXPORTER_OTLP_ENDPOINT "http://10.101.0.2:4318" \
        --set OTEL_EXPORTER_OTLP_PROTOCOL "http/protobuf" \
        --set OTEL_SERVICE_NAME "grok-cli" \
        --set OTEL_LOG_USER_PROMPTS "false" \
        --set OTEL_LOG_TOOL_DETAILS "false"
    '';
  };
in
{
  imports = [
    ./vim/default.nix
    ./git.nix
  ];

  programs.password-store = {
    enable = true;
    settings = {
      PASSWORD_STORE_DIR = "${config.xdg.dataHome}/password-store";
    };
  };

  # Auto-sync password store from keybase git
  systemd.user.services.pass-sync = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Sync password store";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.git}/bin/git -C ${config.programs.password-store.settings.PASSWORD_STORE_DIR} pull --rebase";
    };
  };

  systemd.user.timers.pass-sync = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Daily password store sync";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  programs.claude-code = {
    enable = true;
    package = inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
    settings = {
      permissions = {
        defaultMode = "bypassPermissions";
      };
      effortLevel = "max";
      skipDangerousModePermissionPrompt = true;
      # Never prune session transcripts (default is 30 days); we lost the
      # March 2026 kitten-video sessions to this.
      cleanupPeriodDays = 99999;
      enabledPlugins = {
        "rust-analyzer-lsp@claude-plugins-official" = true;
      };
      attribution = {
        commit = "";
        pr = "";
      };
      env = {
        CLAUDE_CODE_ENABLE_TELEMETRY = "0";
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
        CLAUDE_CODE_DISABLE_TERMINAL_TITLE = "1";
        DISABLE_AUTOUPDATER = "1";
        DISABLE_BUG_COMMAND = "1";
        DISABLE_COST_WARNINGS = "1";
        DISABLE_ERROR_REPORTING = "1";
        DISABLE_NON_ESSENTIAL_MODEL_CALLS = "1";
        DISABLE_TELEMETRY = "1";
      };
    };
  };

  # One global instruction source for all coding agents. Codex reads
  # ~/.codex/AGENTS.md, Claude Code reads ~/.claude/CLAUDE.md, and pi reads
  # ~/.pi/agent/AGENTS.md.
  home.file = {
    ".codex/AGENTS.md".source = ./ai-agent-instructions.md;
    ".claude/CLAUDE.md".source = ./ai-agent-instructions.md;
    ".pi/agent/AGENTS.md".source = ./ai-agent-instructions.md;

    # pi-coding-agent global settings. No home-manager module exists yet, so
    # manage the JSON directly. Note: the store symlink is read-only, so pi's
    # /settings TUI can't persist changes — edit here instead.
    ".pi/agent/settings.json".text = builtins.toJSON {
      defaultProvider = "anthropic";
      # Skip per-project trust prompts, same spirit as claude-code's
      # bypassPermissions above.
      defaultProjectTrust = "always";
      # Anonymous install/update ping to pi.dev; update checks are disabled
      # separately via PI_SKIP_VERSION_CHECK below.
      enableInstallTelemetry = false;
    };
  };

  home.sessionVariables = {
    # AITER's fallback copies its JIT sources from the immutable Nix store to
    # ~/.aiter while preserving mode 0555, then tries to create build/ there.
    # Select a writable, persistent cache before AITER imports its JIT module.
    AITER_JIT_DIR = "${config.xdg.cacheHome}/aiter/jit";

    # pi is nix-managed; its self-updater and version check are useless here.
    PI_SKIP_VERSION_CHECK = "1";
    PI_TELEMETRY = "0";

    # Grok Build is Nix-managed. Disable its updater and every optional
    # client-side reporting path independently.
    GROK_DISABLE_AUTOUPDATER = "1";
    GROK_TELEMETRY_ENABLED = "0";
    GROK_TELEMETRY_TRACE_UPLOAD = "0";
    GROK_FEEDBACK_ENABLED = "0";
    GROK_CRASH_HANDLER = "0";
  };

  # Keep plain `pi` useful for both hosted providers and an ad-hoc local
  # OpenAI-compatible server.  The local wrapper discovers vLLM's effective
  # max_model_len instead of letting Pi assume a larger context window.
  programs.zsh.initContent = lib.mkAfter ''
    pi() {
      if { [[ -n "''${OPENAI_BASE_URL:-}" ]] && [[ -n "''${OPENAI_MODEL:-''${PI_MODEL:-}}" ]]; } || \
         { [[ -n "''${ANTHROPIC_BASE_URL:-}" ]] && [[ -n "''${ANTHROPIC_MODEL:-''${PI_MODEL:-}}" ]]; }; then
        command pi-wrap "$@"
      else
        command pi "$@"
      fi
    }
  '';

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
    stdlib = ''
      # Keep per-project direnv/nix-direnv layouts off shared source trees.
      direnv_layout_dir() {
        local dir base hash state_home

        dir="$(pwd -P)"
        base="''${dir##*/}"
        if [ -z "$base" ]; then
          base=root
        fi

        hash="$(printf '%s' "$dir" | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -d ' ' -f 1)"
        state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"

        echo "$state_home/direnv/layouts/$base-$hash"
      }
    '';
  };

  programs.git.lfs.enable = true;

  # Lorri for nix-shell caching
  services.lorri.enable = lib.mkIf pkgs.stdenv.isLinux true;
  systemd.user.services.lorri.Service = lib.mkIf pkgs.stdenv.isLinux {
    ProtectHome = lib.mkForce "false";
    ProtectSystem = lib.mkForce "full";
  };

  home.packages =
    (with pkgs; [
      nixpkgs-fmt

      # platforms
      gh
      doctl

      # go tooling
      go
      gopls

      # saas crap
      runpodctl

      # fml
      nodejs
      docker-compose

      home-assistant-cli
      home-assistant-cli-go

      # virt-manager
      # virt-viewer

      sox
    ])
    ++ (with inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}; [
      # gemini-cli is being deprecated (June 18, 2026) for unpaid/Google One
      # users; antigravity is Google's unified multi-agent replacement.
      antigravity-cli
      # Self-improving AI agent by Nous Research — creates skills from
      # experience and runs anywhere.
      hermes-agent
      # pi-coding-agent (Mario Zechner) — minimal terminal coding agent with
      # multi-model support; configured via ~/.pi/agent above.
      pi
      # Moonshot's Kimi Code CLI (their curl|bash installer doesn't suit
      # NixOS; nix-ai-tools packages it as of Feb 2026).
      kimi-code
      # SST's opencode — terminal AI coding agent; also runs a headless
      # server (`opencode serve`) exposed on the LAN via opencode-server on trex.
      opencode
      # codex
    ])
    ++ [
      # xAI's Grok Build CLI. Vendor telemetry remains disabled above; this
      # wrapper enables only its content-free external OTel stream to ax102.
      grokWithPrivateOtel
      inputs.nix-strix-halo.packages.${pkgs.stdenv.hostPlatform.system}.pi-wrap
    ]
    ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
      # evm tooling
      # solc
      # foundry-bin
    ];
}
