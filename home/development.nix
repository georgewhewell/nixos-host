{ config
, lib
, pkgs
, inputs
, ...
}:
let
  grokPackage = inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.grok;
  ompPackage = inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.omp;
  ompRpc = pkgs.python3Packages.buildPythonPackage {
    pname = "omp-rpc";
    version = "0.1.0";
    pyproject = true;
    src = "${ompPackage.src}/python/omp-rpc";
    # Built-in OAuth catalogs may intentionally leave token limits unknown.
    # The RPC wire represents those values as JSON null; normalize them to the
    # dataclass's existing unknown sentinel instead of crashing before the
    # first prompt. This is required by xai-oauth/grok-4.6 today.
    postPatch = ''
      substituteInPlace src/omp_rpc/protocol.py \
        --replace-fail 'context_window=int(payload.get("contextWindow", 0)),' 'context_window=int(payload.get("contextWindow") or 0),' \
        --replace-fail 'max_tokens=int(payload.get("maxTokens", 0)),' 'max_tokens=int(payload.get("maxTokens") or 0),'
    '';
    build-system = [ pkgs.python3Packages.setuptools ];
    pythonImportsCheck = [ "omp_rpc" ];
  };
  ompRpcPython = pkgs.python3.withPackages (_: [ ompRpc ]);
  ompRpcPythonWrapper = pkgs.writeShellScriptBin "omp-rpc-python" ''
    exec ${ompRpcPython}/bin/python3 "$@"
  '';
  codexCli = inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.codex;
  codexAccounts = pkgs.stdenvNoCC.mkDerivation {
    pname = "codex-accounts";
    version = "0.1.4";
    src = pkgs.fetchFromGitHub {
      owner = "omarhoumz";
      repo = "codex-accounts";
      rev = "v0.1.4";
      hash = "sha256-JE+p7QcvGK95tVBdmXbK+nEosP3vnQiwLG5541JirEk=";
    };
    nativeBuildInputs = [ pkgs.makeWrapper ];
    installPhase = ''
      runHook preInstall
      install -d "$out/share/codex-accounts" "$out/bin"
      cp -R bin lib shell completions "$out/share/codex-accounts/"
      patchShebangs "$out/share/codex-accounts/bin"
      for tool in codex-accounts codex-switch codex-run; do
        makeWrapper "$out/share/codex-accounts/bin/$tool" "$out/bin/$tool" \
          --prefix PATH : ${lib.makeBinPath [
            pkgs.bash
            pkgs.coreutils
            pkgs.gawk
            pkgs.gnugrep
            pkgs.gnused
            pkgs.jq
            codexCli
          ]}
      done
      runHook postInstall
    '';
    meta = {
      description = "Manage multiple OpenAI Codex CLI accounts";
      homepage = "https://github.com/omarhoumz/codex-accounts";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
    };
  };
  # OMP deliberately keeps credentials in its own SQLite store, while the
  # existing pi install keeps the OpenRouter key in ~/.pi/agent/auth.json.
  # Bridge the two at process start without copying the key into the Nix
  # store, a generated config file, or the shell history. The OTel exports
  # mirror `grokWithPrivateOtel` below: the agent core reads the standard
  # OTEL_* env vars and registers an OTLP/proto MeterProvider that emits
  # GenAI-semconv `gen_ai.client.token.usage` plus `pi.omp.agent.*`
  # counters/histograms (runs, steps, chat/tool calls by name+status+finish
  # reason, latencies, estimated cost). The trex OTel collector accepts
  # http/protobuf on :4318 and forwards to VictoriaMetrics (see
  # services/otel-collector.nix). Only `http/protobuf` is supported; any
  # other transport declines rather than misroutes.
  ompWithPiAuth = pkgs.writeShellScriptBin "omp" ''
    set -euo pipefail
    if [[ -z "''${OPENROUTER_API_KEY:-}" ]]; then
      pi_auth="''${HOME}/.pi/agent/auth.json"
      if [[ -r "$pi_auth" ]]; then
        openrouter_key="$(${pkgs.jq}/bin/jq -er '.openrouter.key // empty' "$pi_auth" 2>/dev/null || true)"
        if [[ -n "$openrouter_key" ]]; then
          export OPENROUTER_API_KEY="$openrouter_key"
        fi
      fi
    fi
    if [[ -z "''${LLMAPI_API_KEY:-}" ]]; then
      pi_auth="''${HOME}/.pi/agent/auth.json"
      if [[ -r "$pi_auth" ]]; then
        llmapi_key="$(${pkgs.jq}/bin/jq -er '.llmapi.key // empty' "$pi_auth" 2>/dev/null || true)"
        if [[ -n "$llmapi_key" ]]; then
          export LLMAPI_API_KEY="$llmapi_key"
        fi
      fi
    fi
    if [[ -z "''${DEEPSEEK_API_KEY:-}" ]]; then
      pi_auth="''${HOME}/.pi/agent/auth.json"
      if [[ -r "$pi_auth" ]]; then
        deepseek_key="$(${pkgs.jq}/bin/jq -er '.deepseek.key // empty' "$pi_auth" 2>/dev/null || true)"
        if [[ -n "$deepseek_key" ]]; then
          export DEEPSEEK_API_KEY="$deepseek_key"
        fi
      fi
    fi
    # OTel metric export — collective enable, not per-signal. The collector's
    # logs pipeline (services/otel-collector.nix) accepts OTel logs as `nop`,
    # so locals aren't worth exporting; disable to keep OMP's CPU quiet.
    export OTEL_EXPORTER_OTLP_ENDPOINT="''${OTEL_EXPORTER_OTLP_ENDPOINT:-http://trex:4318}"
    export OTEL_EXPORTER_OTLP_PROTOCOL="''${OTEL_EXPORTER_OTLP_PROTOCOL:-http/protobuf}"
    export OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE="''${OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE:-cumulative}"
    export OTEL_METRICS_EXPORTER="''${OTEL_METRICS_EXPORTER:-otlp}"
    export OTEL_LOGS_EXPORTER="''${OTEL_LOGS_EXPORTER:-none}"
    export OTEL_TRACES_EXPORTER="''${OTEL_TRACES_EXPORTER:-otlp}"
    export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-omp-cli}"
    exec ${ompPackage}/bin/omp "$@"
  '';
  # All AI CLIs ship content-free OTel metrics to the collector on trex
  # (services/otel-collector.nix), which writes them into victoriametrics.
  otelEndpoint = "http://trex:4318";
  grokWithPrivateOtel = pkgs.symlinkJoin {
    name = "grok-private-otel";
    paths = [ grokPackage ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/grok \
        --set GROK_EXTERNAL_OTEL "1" \
        --set OTEL_METRICS_EXPORTER "otlp" \
        --set OTEL_LOGS_EXPORTER "none" \
        --set OTEL_EXPORTER_OTLP_ENDPOINT "${otelEndpoint}" \
        --set OTEL_EXPORTER_OTLP_PROTOCOL "http/protobuf" \
        --set OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE "cumulative" \
        --set OTEL_SERVICE_NAME "grok-cli" \
        --set OTEL_LOG_USER_PROMPTS "false" \
        --set OTEL_LOG_TOOL_DETAILS "false"
    '';
  };

  # Directory trust (Codex/Claude/Grok/Antigravity/opencode) now lives in
  # ./agent-trust.nix -- a single `programs.agentDirectoryTrust`
  # option (`.roots`/`.projects`/`.extraPaths`, wired up in the `config`
  # block below) that every tool derives its own config from. Pure
  # evaluation, no filesystem access: `projects` is a curated,
  # hand-maintained list (recovered from commit c5d3da5's
  # `agentTrustedDirs`), not auto-discovered. See that file for the
  # per-tool research (glob support, ancestor trust, the two places a
  # mutable-state activation merge is still unavoidable).
  #
  # Codex's non-trust settings. `projects` (the trust table) is merged in
  # below from `config.programs.agentDirectoryTrust.paths` when building
  # the attrset that `home.activation.codexTrustedProjects` writes to
  # config.toml -- the DECLARATION lives in the Nix module now, but the
  # file itself is still materialised by that same writable-file
  # activation script (see the comment there for why).
  codexSettings = {
    model = "gpt-6-astra";
    model_reasoning_effort = "medium";
    approval_policy = "never";
    features = {
      terminal_resize_reflow = true;
      context_management.experimental_mode = true;
    };
    tui = {
      resume_cwd = "session";
      model_availability_nux = {
        "gpt-5.5" = 4;
        "gpt-5.6-sol" = 4;
        "gpt-6-astra" = 4;
      };
    };
    notice.hide_rate_limit_model_nudge = true;
    analytics.enabled = false;
    otel = {
      environment = "prod";
      log_user_prompt = false;
      metrics_exporter.otlp-http = {
        endpoint = "http://trex:4318/v1/metrics";
        protocol = "binary";
      };
    };
    # The declaration: which directories Codex should treat as trusted.
    # Sourced from the shared module (./agent-trust.nix) instead of a
    # literal list here, so this can't drift from Claude/Grok/Antigravity's
    # trust lists.
    projects = lib.genAttrs config.programs.agentDirectoryTrust.paths
      (_: { trust_level = "trusted"; });
  };

  # Used by the codex config.toml merge activation script below: a
  # read-merge-write that preserves keys Codex itself has written (e.g.
  # trust decisions accepted interactively for directories outside
  # `codexSettings.projects`) instead of clobbering the file.
  python3WithTomlkit = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);

  # `codexSettings` as a real Nix-store file, read by that same script.
  # NOT embedded as a `r'''${...}'''` string literal: Nix's indented
  # (`''...''`) string escaping treats three consecutive single quotes as
  # an escape for a literal two-quote run, so `'''` in the *source* comes
  # out as `''` in the *generated* script -- silently turning the Python
  # raw-string delimiter into a 2-quote empty string followed by garbage.
  # (Confirmed the hard way: built and ran the previous version of this
  # script standalone -- SyntaxError, every single time. `colmena build`
  # never catches this class of bug, since the activation script is just
  # text to the build; it is never executed until real activation.)
  # Passing the JSON as a file path sidesteps the whole class of
  # string-escaping hazard.
  codexSettingsJSON = pkgs.writeText "codex-settings.json" (builtins.toJSON codexSettings);
in
{
  imports = [
    ./vim/default.nix
    ./git.nix
    ./agent-trust.nix
  ];

  # The single place to add a new trusted project root -- every tool's
  # config below derives from `config.programs.agentDirectoryTrust.{roots,paths}`.
  # `roots` defaults to `[ "/mnt/Home/src" ]` (see ./agent-trust.nix);
  # `extraPaths` carries forward one-off directories outside that tree
  # (mostly /home/grw/src/*) that were trusted by hand before this module
  # existed.
  programs.agentDirectoryTrust = {
    enable = true;
    extraPaths = [
      "/home/grw"
      "/home/grw/src"
      "/home/grw/src/george-admin"
      "/home/grw/src/hellas-admin"
      "/home/grw/src/nixos-nanokvm"
      "/home/grw/src/nix-llamacpp-rocm"
      "/home/grw/src/linux-libibverbs-usb4"
      "/home/grw/src/hellas-esp32"
      "/mnt/Home/pde"
      "/tmp/nanokvm-checkout"
      "/tmp/ds4-src"
    ];
  };

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

  # NOTE: `settings` is deliberately left at its default ({ }), not set to
  # `codexSettings`. The upstream module writes `programs.codex.settings`
  # to `~/.codex/config.toml` via `home.file`, which home-manager
  # materialises as a symlink into the read-only Nix store. Codex's own
  # "do you trust this folder?" dialog persists its answer by rewriting
  # that exact file (`config/batchWrite` in the app-server); against a
  # store symlink that write fails outright:
  #   Failed to set trust for <dir>: config/batchWrite failed in TUI:
  #   failed to persist config.toml: failed to persist config at
  #   /nix/store/...-codex-config (code -32603)
  # so trust could never actually be saved, declared config or not, for
  # ANY directory not already in the declared list -- including one you
  # want to trust for the first time right now. This is the one
  # deliberate, permanent exception in this whole scheme: Codex keeps a
  # real, writable config.toml, not a store symlink, forever -- not just
  # until the declared list covers everything. `home.activation
  # .codexTrustedProjects` below owns config.toml directly and merges
  # `codexSettings` (including its `projects` trust table, itself sourced
  # from `programs.agentDirectoryTrust.paths` above) into it, preserving
  # anything Codex itself has since written (e.g. later interactive trust
  # decisions for directories outside `codexSettings.projects`).
  programs.codex = {
    enable = true;
    package = codexCli;
  };

  # Make ~/.codex/config.toml a real, writable file (see the note on
  # `programs.codex` above) and merge `codexSettings` into it idempotently.
  # `entryAfter [ "writeBoundary" ]` matches the existing
  # `qwen38AgentModels` precedent: it runs after home-manager has linked (and
  # cleaned up stale) home.file entries, so by the time this runs, home-manager
  # will already have removed its own config.toml symlink now that
  # `programs.codex.settings` is unset. The explicit store-symlink check below
  # is a defensive belt-and-braces for the first activation after upgrading
  # from an older generation (or after the brief period this repo tried
  # `programs.codex.settings` directly), or if that ordering assumption
  # ever changes.
  home.activation.codexTrustedProjects = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -eu
    codex_dir="$HOME/.codex"
    codex_config="$codex_dir/config.toml"
    ${pkgs.coreutils}/bin/mkdir -p "$codex_dir"

    if [ -L "$codex_config" ]; then
      link_target=$(${pkgs.coreutils}/bin/readlink -f "$codex_config" 2>/dev/null || true)
      case "$link_target" in
        /nix/store/*)
          echo "codex: config.toml is a read-only store symlink, replacing with a writable copy" >&2
          ${pkgs.coreutils}/bin/cat "$codex_config" > "$codex_config.rw" 2>/dev/null || : > "$codex_config.rw"
          ${pkgs.coreutils}/bin/rm -f "$codex_config"
          ${pkgs.coreutils}/bin/mv "$codex_config.rw" "$codex_config"
          ;;
      esac
    fi
    [ -e "$codex_config" ] || : > "$codex_config"

    ${python3WithTomlkit}/bin/python3 - "$codex_config" "${codexSettingsJSON}" <<'PYEOF' || echo "codex: config.toml merge failed, left the file untouched" >&2
import json
import os
import sys
from collections.abc import Mapping

import tomlkit

path = sys.argv[1]
with open(sys.argv[2], "r", encoding="utf-8") as fh:
    desired = json.load(fh)

def merge(table, values):
    for key, value in values.items():
        if isinstance(value, dict):
            existing = table.get(key)
            if not isinstance(existing, Mapping):
                existing = tomlkit.table()
                table[key] = existing
            merge(existing, value)
        else:
            table[key] = value

try:
    with open(path, "r", encoding="utf-8") as fh:
        doc = tomlkit.parse(fh.read())
except Exception as exc:  # malformed file: never block activation
    print(f"codex: config.toml unreadable/invalid TOML ({exc}), leaving untouched", file=sys.stderr)
    sys.exit(0)

try:
    merge(doc, desired)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(tomlkit.dumps(doc))
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
except Exception as exc:
    print(f"codex: config.toml merge raised {exc}, leaving untouched", file=sys.stderr)
    sys.exit(0)
PYEOF
  '';

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
        # OTel metrics (per-model tokens, cost, session counters) to the
        # collector on trex. Vendor telemetry (Statsig/Sentry) stays disabled
        # below — this stream is self-hosted and content-free (no prompts).
        CLAUDE_CODE_ENABLE_TELEMETRY = "1";
        OTEL_METRICS_EXPORTER = "otlp";
        OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
        OTEL_EXPORTER_OTLP_ENDPOINT = "http://trex:4318";
        OTEL_METRIC_EXPORT_INTERVAL = "60000";
        # Prometheus-backed store: delta (the default) would be dropped.
        OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE = "cumulative";
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

  # Claude Code, Grok Build, and Antigravity/Gemini directory trust is now
  # wired up in ./agent-trust.nix (imported above) from
  # `programs.agentDirectoryTrust.paths` -- see that file for what's a real
  # declarative `home.file` (Grok) vs. the two tools whose trust state
  # coexists with other tool-owned mutable data and so still needs a
  # minimal activation merge (Claude Code, Antigravity).

  # One global instruction source for all coding agents. Codex reads
  # ~/.codex/AGENTS.md, Claude Code reads ~/.claude/CLAUDE.md, and pi reads
  # ~/.pi/agent/AGENTS.md.
  home.file = {
    ".codex/AGENTS.md".source = ./ai-agent-instructions.md;
    ".claude/CLAUDE.md".source = ./ai-agent-instructions.md;
    ".pi/agent/AGENTS.md".source = ./ai-agent-instructions.md;
    # agy (Google antigravity-cli) and opencode read their own conventional
    # paths, so the same file has to be linked there too or those two agents
    # start with no environment guidance at all.
    ".gemini/GEMINI.md".source = ./ai-agent-instructions.md;
    ".config/opencode/AGENTS.md".source = ./ai-agent-instructions.md;

    # pi-coding-agent global settings. No home-manager module exists yet, so
    # manage the JSON directly. Note: the store symlink is read-only, so pi's
    # /settings TUI can't persist changes — edit here instead.
    ".pi/agent/settings.json".text = builtins.toJSON {
      defaultProvider = "mbp-qwen38";
      defaultModel = "qwen38-dense";
      # Skip per-project trust prompts, same spirit as claude-code's
      # bypassPermissions above.
      defaultProjectTrust = "always";
      # Anonymous install/update ping to pi.dev; update checks are disabled
      # separately via PI_SKIP_VERSION_CHECK below.
      enableInstallTelemetry = false;
    };

    # OMP's model/provider registry. The model id is intentionally the July
    # snapshot, not OpenRouter's mutable `latest` alias. The apiKey value is
    # only an environment-variable name; ompWithPiAuth obtains that variable
    # from the existing Pi credential file at runtime.
    ".omp/agent/models.yml".text = ''
      providers:
        strix-qwen38:
          baseUrl: http://strix-2:30800/v1
          api: openai-completions
          auth: none
          models:
            - id: qwen38
              name: Qwen3.8-27B (TP4 V620)
              reasoning: true
              input: [text]
              contextWindow: 32768
              maxTokens: 8192
              compat:
                supportsDeveloperRole: false
                supportsReasoningEffort: false
                maxTokensField: max_tokens
        mbp-qwen38:
          baseUrl: http://127.0.0.1:18150/v1
          api: openai-completions
          auth: none
          models:
            - id: qwen38-dense
              name: Qwen3.8-27B BF16 (MBP)
              reasoning: true
              input: [text]
              contextWindow: 32768
              maxTokens: 8192
              compat:
                supportsDeveloperRole: false
                supportsReasoningEffort: false
                maxTokensField: max_tokens
        # Grok Build exposes 4.6 through the subscription OAuth catalog before
        # OMP 17.2.15's curated xai-oauth table knows its limits/effort dial.
        # Keep authentication and transport built-in; fill only the metadata
        # reported by the signed-in Grok model catalog on trex.
        xai-oauth:
          modelOverrides:
            grok-4.6:
              name: Grok 4.6
              reasoning: true
              input: [text]
              contextWindow: 500000
              maxTokens: 500000
              compat:
                supportsReasoningEffort: true
                omitReasoningEffort: false
                reasoningEffortMap:
                  minimal: low
                includeEncryptedReasoning: false
                filterReasoningHistory: true
                supportsImageDetailOriginal: false
        openrouter:
          baseUrl: https://openrouter.ai/api/v1
          api: openai-completions
          apiKey: OPENROUTER_API_KEY
          models:
            - id: deepseek/deepseek-v4-flash-0731
              name: DeepSeek V4 Flash 0731 (OpenRouter)
              reasoning: true
              input: [text]
              contextWindow: 1048576
              maxTokens: 384000
              compat:
                # DeepSeek/OpenRouter thinking requests reject these shapes.
                supportsDeveloperRole: false
                supportsToolChoice: false
                supportsForcedToolChoice: false
                supportsReasoningEffort: true
                maxTokensField: max_tokens
                reasoningContentField: reasoning_content
                replayReasoningContent: true
                requiresReasoningContentForToolCalls: true
                allowsSyntheticReasoningContentForToolCalls: false
                requiresAssistantContentForToolCalls: true
                thinkingFormat: openrouter
        opencode-free:
          baseUrl: https://opencode.ai/zen/v1
          api: openai-completions
          auth: none
          models:
            - id: deepseek-v4-flash-free
              name: DeepSeek V4 Flash Free (observed anonymous route)
              reasoning: true
              input: [text]
              contextWindow: 200000
              maxTokens: 128000
              compat:
                supportsDeveloperRole: false
                supportsToolChoice: false
                supportsForcedToolChoice: false
                supportsReasoningEffort: true
                maxTokensField: max_tokens
                reasoningContentField: reasoning_content
                replayReasoningContent: true
                requiresReasoningContentForToolCalls: true
                allowsSyntheticReasoningContentForToolCalls: false
                requiresAssistantContentForToolCalls: true
        # DeepSeek's first-party API. Deliberately NOT the default provider:
        # the account is pay-as-you-go and, as of 2026-09-03, sits at $0.00
        # with is_available=false, so every request returns HTTP 402
        # Insufficient Balance. This route is here for the moment it is topped
        # up; llm-quota-exporter's `deepseek` provider reports the balance and
        # saturates its `serviceable` window while the account cannot answer.
        # The same models are reachable today through the openrouter route
        # above, which has credit. apiKey is an env-var name, bridged from
        # ~/.pi/agent/auth.json by ompWithPiAuth.
        deepseek:
          baseUrl: https://api.deepseek.com
          api: openai-completions
          apiKey: DEEPSEEK_API_KEY
          models:
            - id: deepseek-v4-flash
              name: DeepSeek V4 Flash (first-party)
              reasoning: true
              input: [text]
              contextWindow: 1048576
              maxTokens: 384000
              compat:
                # Same thinking-request constraints as the OpenRouter route.
                supportsDeveloperRole: false
                supportsToolChoice: false
                supportsForcedToolChoice: false
                supportsReasoningEffort: true
                maxTokensField: max_tokens
                reasoningContentField: reasoning_content
                replayReasoningContent: true
                requiresReasoningContentForToolCalls: true
                allowsSyntheticReasoningContentForToolCalls: false
                requiresAssistantContentForToolCalls: true
            - id: deepseek-v4-pro
              name: DeepSeek V4 Pro (first-party)
              reasoning: true
              input: [text]
              contextWindow: 1048576
              maxTokens: 384000
              compat:
                supportsDeveloperRole: false
                supportsToolChoice: false
                supportsForcedToolChoice: false
                supportsReasoningEffort: true
                maxTokensField: max_tokens
                reasoningContentField: reasoning_content
                replayReasoningContent: true
                requiresReasoningContentForToolCalls: true
                allowsSyntheticReasoningContentForToolCalls: false
                requiresAssistantContentForToolCalls: true
        # LLMAPI relay (llmapi.pro) in both protocols, keyed by the same
        # sk-relay key from ~/.pi/agent/auth.json, bridged by ompWithPiAuth.
        llmapi:
          baseUrl: https://llmapi.pro
          api: anthropic-messages
          apiKey: LLMAPI_API_KEY
          models:
            - id: claude-fable-5
              name: Claude Fable 5
              reasoning: true
              input: [text, image]
              contextWindow: 1000000
              maxTokens: 128000
            - id: claude-opus-5
              name: Claude Opus 5
              reasoning: true
              input: [text, image]
              contextWindow: 1000000
              maxTokens: 128000
            - id: claude-sonnet-5
              name: Claude Sonnet 5
              reasoning: true
              input: [text, image]
              contextWindow: 1000000
              maxTokens: 128000
            - id: claude-haiku-4-5-20251001
              name: Claude Haiku 4.5
              reasoning: false
              input: [text, image]
              contextWindow: 200000
              maxTokens: 64000
        openai-llmapi:
          baseUrl: https://llmapi.pro/v1
          api: openai-completions
          apiKey: LLMAPI_API_KEY
          models:
            - id: claude-fable-5
              name: Claude Fable 5
              reasoning: true
              input: [text, image]
              contextWindow: 1000000
              maxTokens: 128000
            - id: claude-opus-5
              name: Claude Opus 5
              reasoning: true
              input: [text, image]
              contextWindow: 1000000
              maxTokens: 128000
            - id: claude-sonnet-5
              name: Claude Sonnet 5
              reasoning: true
              input: [text, image]
              contextWindow: 1000000
              maxTokens: 128000
            - id: claude-haiku-4-5-20251001
              name: Claude Haiku 4.5
              reasoning: false
              input: [text, image]
              contextWindow: 200000
              maxTokens: 64000
            - id: gpt-5.6-sol
              name: GPT-5.6 Sol
              reasoning: true
              input: [text, image]
              contextWindow: 200000
              maxTokens: 65536
            - id: gpt-5.6-luna
              name: GPT-5.6 Luna
              reasoning: true
              input: [text, image]
              contextWindow: 200000
              maxTokens: 65536
            - id: gpt-5.6-terra
              name: GPT-5.6 Terra
              reasoning: true
              input: [text, image]
              contextWindow: 200000
              maxTokens: 65536
            - id: gpt-5.6-sol-codex
              name: GPT-5.6 Sol Codex
              reasoning: true
              input: [text, image]
              contextWindow: 200000
              maxTokens: 65536
            - id: gpt-5.6-codex
              name: GPT-5.6 Codex
              reasoning: true
              input: [text, image]
              contextWindow: 200000
              maxTokens: 65536
            - id: gpt-5-pro
              name: GPT-5 Pro
              reasoning: true
              input: [text, image]
              contextWindow: 400000
              maxTokens: 65536
            - id: gpt-5
              name: GPT-5
              reasoning: true
              input: [text, image]
              contextWindow: 400000
              maxTokens: 65536
            - id: gpt-5-mini
              name: GPT-5 Mini
              reasoning: true
              input: [text, image]
              contextWindow: 400000
              maxTokens: 65536
            - id: gpt-5-nano
              name: GPT-5 Nano
              reasoning: false
              input: [text, image]
              contextWindow: 200000
              maxTokens: 65536
            - id: gpt-4o
              name: GPT-4o
              reasoning: true
              input: [text, image]
              contextWindow: 128000
              maxTokens: 16384
    '';

    # Keep the confidential/acceptance parent on the exact paid 0731 snapshot,
    # while bounded task fan-out is explicitly free-first through the observed
    # anonymous OpenCode Zen endpoint. This custom route is non-contractual;
    # there is no automatic fallback to paid OpenRouter. Never send secrets,
    # vendor bytes, or confidential input to the free route. The built-in
    # opencode-zen provider remains available separately when OPENCODE_API_KEY
    # is supplied.
    ".omp/agent/config.yml".text = ''
      # This file is an immutable Home Manager symlink, so OMP's interactive
      # setup wizard cannot persist its completion marker here.  Keep the
      # marker declarative and suppress onboarding for task-specific --config
      # overlays; those overlays augment this profile rather than replacing it.
      setupVersion: 1
      startup:
        setupWizard: false
      defaultThinkingLevel: high
      modelRoles:
        default: mbp-qwen38/qwen38-dense
        task: mbp-qwen38/qwen38-dense
        smol: mbp-qwen38/qwen38-dense
      async:
        enabled: true
        maxJobs: 8
      retry:
        modelFallback: false
        fallbackChains: {}
      task:
        batch: true
        eager: preferred
        prewalk: false
        maxConcurrency: 4
        maxRecursionDepth: 1
        isolation:
          mode: auto
          apply: false
          merge: patch
    '';
  };

  # Pi and OpenCode keep credentials and user-added providers in mutable JSON
  # files. Merge the local Qwen endpoints into those files at activation time
  # instead of replacing either file (and, in OpenCode's case, copying secrets
  # into the Nix store).
  home.activation.qwen38AgentModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -eu

    pi_dir="$HOME/.pi/agent"
    pi_models="$pi_dir/models.json"
    ${pkgs.coreutils}/bin/mkdir -p "$pi_dir"
    if [[ ! -s "$pi_models" ]] || ! ${pkgs.jq}/bin/jq -e 'type == "object"' "$pi_models" >/dev/null 2>&1; then
      ${pkgs.coreutils}/bin/printf '%s\n' '{"providers":{}}' > "$pi_models"
    fi
    ${pkgs.jq}/bin/jq '
      .providers = (.providers // {}) |
      .providers["strix-qwen38"] = {
        "name": "Qwen3.8-27B on strix-2 V620s",
        "baseUrl": "http://strix-2:30800/v1",
        "api": "openai-completions",
        "apiKey": "none",
        "compat": {
          "supportsDeveloperRole": false,
          "supportsReasoningEffort": false
        },
        "models": [{
          "id": "qwen38",
          "name": "Qwen3.8-27B (TP4 V620)",
          "reasoning": true,
          "input": ["text"],
          "contextWindow": 32768,
          "maxTokens": 8192,
          "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
        }]
      } |
      .providers["mbp-qwen38"] = {
        "name": "Qwen3.8-27B vLLM Metal on MBP",
        "baseUrl": "http://127.0.0.1:18150/v1",
        "api": "openai-completions",
        "apiKey": "none",
        "compat": {
          "supportsDeveloperRole": false,
          "supportsReasoningEffort": false
        },
        "models": [{
          "id": "qwen38-dense",
          "name": "Qwen3.8-27B BF16 (MBP)",
          "reasoning": true,
          "input": ["text"],
          "contextWindow": 32768,
          "maxTokens": 8192,
          "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
        }]
      }
    ' "$pi_models" > "$pi_models.new"
    ${pkgs.coreutils}/bin/chmod 0600 "$pi_models.new"
    ${pkgs.coreutils}/bin/mv "$pi_models.new" "$pi_models"

    # dsh's user patch layer for the `web` profile. dsh ships only the
    # deepseek-official route, which is useless while that account sits at
    # $0.00, so give it the providers that actually have credit. Catalog routes
    # (openrouter, deepseek) inherit endpoint/protocol/model list from pi-ai;
    # the local llama.cpp endpoints are hand-declared because pi-ai ships
    # nothing under those keys. apiKeyEnv is a credential *reference* resolved
    # per request, so no key enters this file or the store.
    #
    # Only written when dsh has already initialised the profile: the directory
    # also needs package.json/pnpm-workspace.yaml/node_modules that initProfile
    # creates, and racing it would leave a half-built profile.
    dsh_profile="$HOME/.dsh/profiles/web"
    if [[ -d "$dsh_profile" ]]; then
      ${pkgs.coreutils}/bin/cat > "$dsh_profile/cordis.patch.yml.new" <<'DSHPATCH'
# Managed by home/development.nix -- edit there, not here.
- id: llm-pi-ai
  config:
    providers:
      openrouter:
        apiKeyEnv: OPENROUTER_API_KEY
      deepseek:
        apiKeyEnv: DEEPSEEK_API_KEY
      mbp-qwen38:
        displayName: Qwen3.8-27B BF16 (MBP)
        api: openai-completions
        baseURL: http://127.0.0.1:18150/v1
        models:
          - id: qwen38-dense
            name: Qwen3.8-27B BF16 (MBP)
            contextWindow: 32768
            maxTokens: 8192
      strix-qwen38:
        displayName: Qwen3.8-27B (TP4 V620)
        api: openai-completions
        baseURL: http://strix-2:30800/v1
        models:
          - id: qwen38
            name: Qwen3.8-27B (TP4 V620)
            contextWindow: 32768
            maxTokens: 8192
DSHPATCH
      ${pkgs.coreutils}/bin/mv "$dsh_profile/cordis.patch.yml.new" \
        "$dsh_profile/cordis.patch.yml"
    fi

    # opencode's config.json is a real file it rewrites itself, so merge into
    # it rather than linking it. The deepseek route below takes its key as
    # "{env:DEEPSEEK_API_KEY}", opencode's env-substitution syntax: this jq
    # program lives in the world-readable Nix store, so a literal key here
    # would publish it to every user on the box.
    opencode_dir="$HOME/.config/opencode"
    opencode_config="$opencode_dir/config.json"
    ${pkgs.coreutils}/bin/mkdir -p "$opencode_dir"
    if [[ ! -s "$opencode_config" ]] || ! ${pkgs.jq}/bin/jq -e 'type == "object"' "$opencode_config" >/dev/null 2>&1; then
      ${pkgs.coreutils}/bin/printf '%s\n' '{"$schema":"https://opencode.ai/config.json"}' > "$opencode_config"
    fi
    ${pkgs.jq}/bin/jq --argjson trustedRootGlobs '${builtins.toJSON (map (r: "${r}/**") config.programs.agentDirectoryTrust.roots)}' '
      .provider = (.provider // {}) |
      .provider["strix-qwen38"] = {
        "npm": "@ai-sdk/openai-compatible",
        "name": "Qwen3.8-27B on strix-2 V620s",
        "options": {"baseURL": "http://strix-2:30800/v1"},
        "models": {"qwen38": {
          "name": "Qwen3.8-27B (TP4 V620)",
          "reasoning": true,
          "limit": {"context": 32768, "output": 8192},
          "tool_call": true
        }}
      } |
      .provider["mbp-qwen38"] = {
        "npm": "@ai-sdk/openai-compatible",
        "name": "Qwen3.8-27B BF16 on MBP",
        "options": {"baseURL": "http://127.0.0.1:18150/v1", "apiKey": "unused"},
        "models": {"qwen38-dense": {
          "name": "Qwen3.8-27B BF16 (MBP)",
          "reasoning": true,
          "limit": {"context": 32768, "output": 8192},
          "tool_call": true
        }}
      } |
      .provider["deepseek"] = {
        "npm": "@ai-sdk/openai-compatible",
        "name": "DeepSeek (first-party)",
        "options": {
          "baseURL": "https://api.deepseek.com",
          "apiKey": "{env:DEEPSEEK_API_KEY}"
        },
        "models": {
          "deepseek-v4-flash": {
            "name": "DeepSeek V4 Flash (first-party)",
            "reasoning": true,
            "limit": {"context": 1048576, "output": 384000},
            "tool_call": true
          },
          "deepseek-v4-pro": {
            "name": "DeepSeek V4 Pro (first-party)",
            "reasoning": true,
            "limit": {"context": 1048576, "output": 384000},
            "tool_call": true
          }
        }
      } |
      # opencode has no single "trust this folder" dialog; the closest
      # equivalent is the external_directory permission (default "ask"),
      # which gates file access outside the directory opencode was
      # launched in, and -- confirmed against
      # https://opencode.ai/docs/permissions/ -- genuinely supports glob
      # keys (the docs example allows an entire tree in one rule), so one
      # rule per root covers its whole tree; no exact-path enumeration
      # needed here. Driven by programs.agentDirectoryTrust.roots so this
      # stays in sync with the other tools trust lists automatically.
      .permission = (.permission // {}) |
      .permission.external_directory = (.permission.external_directory // {}) |
      reduce $trustedRootGlobs[] as $g (.; .permission.external_directory[$g] = "allow") |
      .model = "mbp-qwen38/qwen38-dense"
    ' "$opencode_config" > "$opencode_config.new"
    ${pkgs.coreutils}/bin/chmod 0600 "$opencode_config.new"
    ${pkgs.coreutils}/bin/mv "$opencode_config.new" "$opencode_config"
  '';

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

  programs.zsh.shellAliases = {
    codex-a = "codex-run company";
    codex-b = "codex-run personal";
  };

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
      # pi-coding-agent (Mario Zechner) — minimal terminal coding agent with
      # multi-model support; configured via ~/.pi/agent above.
      pi
      # Oh My Pi — the task/async/isolation-capable Pi fork. The wrapper keeps
      # its OpenRouter credential source identical to the existing Pi setup.
      ompWithPiAuth
      # The matching upstream RPC client owns framing, request correlation,
      # process teardown, and protocol-v2 chunk reassembly for supervisors.
      ompRpcPythonWrapper
      # Moonshot's Kimi Code CLI (their curl|bash installer doesn't suit
      # NixOS; nix-ai-tools packages it as of Feb 2026).
      kimi-code
      # SST's opencode — terminal AI coding agent; also runs a headless
      # server (`opencode serve`) exposed on the LAN via opencode-server on trex.
      opencode
      # DeepSeek's agent harness. `dsh --profile tui` locally; the `web` profile
      # runs as dsh-web on trex behind an authenticating nginx vhost, because
      # dsh itself has no login (see machines/x86/trex/default.nix).
      dsh
    ])
    ++ [
      # xAI's Grok Build CLI. Vendor telemetry remains disabled above; this
      # wrapper enables only its content-free external OTel stream to ax102.
      grokWithPrivateOtel
      codexAccounts
      inputs.nix-strix-halo.packages.${pkgs.stdenv.hostPlatform.system}.pi-wrap
    ]
    ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
      # evm tooling
      # solc
      # foundry-bin
    ];
}
