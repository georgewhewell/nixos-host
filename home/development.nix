{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
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
    Install.WantedBy = ["timers.target"];
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

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
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
      alejandra
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
      antigravity
      # opencode
      # codex
    ])
    ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
      # evm tooling
      # solc
      # foundry-bin
    ];
}
