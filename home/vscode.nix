{pkgs, ...}: {
  imports = [./development.nix];

  home.packages = with pkgs; [
    alejandra
    direnv
    fd
    git
    gh
    nixpkgs-fmt
  ];

  programs.vscode = {
    enable = true;
    mutableExtensionsDir = false;
    profiles.default = {
      userSettings = {
        "update.mode" = "none";
        "extensions.autoUpdate" = false;
        "explorer.confirmDelete" = false;
        "workbench.colorTheme" = "Pitch Black";
        "editor.formatOnSave" = true;
        "editor.formatOnType" = true;
        "editor.inlineSuggest.enabled" = true;
        "editor.codeActionsOnSave" = {
          "source.fixAll" = "explicit";
          "source.organizeImports" = "explicit";
        };
        "[rust]" = {
          #"editor.defaultFormatter" = "rust-lang.rust-analyzer";
          "editor.formatOnSave" = true;
        };
        "[typescript]" = {
          "editor.codeActionsOnSave" = {
            "source.organizeImports" = "never";
          };
        };
        # "remote.SSH.configFile" = pkgs.writeText "vscode-ssh" ''
        #   # Include user SSH config if present
        #   Include ~/.ssh/config

        #   # # ProxyJump logic for satanic.link when OFF the LAN (no 192.168.23.*)
        #   Match host *.satanic.link exec "! (ifconfig 2>/dev/null || ip addr 2>/dev/null) | grep -q '192\.168\.23\.'"
        #     ProxyJump grw@satanic.link

        #   # # Direct connection when ON the LAN
        #   # Match host *.satanic.link exec "(ifconfig 2>/dev/null || ip addr 2>/dev/null) | grep -q '192\.168\.23\.'"
        #   #   ProxyJump none

        #   Host trex.lan.satanic.link
        #     User grw
        # '';
        # "remote.SSH.useLocalServer" = true;
        # "remote.SSH.useExecServer" = false;
        # "remote.SSH.enableDynamicForwarding" = false;
        # "remote.SSH.remoteServerListenOnSocket" = true;
        "remote.SSH.remotePlatform" = {
          "trex.satanic.link" = "linux";
        };
        #  "[python]" = {
        #    "editor.defaultFormatter" = "charliermarsh.ruff";
        #  };
        "[nix]" = {
          #     "editor.defaultFormatter" = "kamadorueda.alejandra";
          "editor.formatOnPaste" = true;
          "editor.formatOnSave" = true;
          "editor.formatOnType" = false;
        };
        "remote.SSH.enableX11Forwarding" = false;
      };
      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide
        hashicorp.terraform
        viktorqvarfordt.vscode-pitch-black-theme
        github.copilot
        # github.copilot-chat
        # rust-lang.rust-analyzer
        ms-vscode-remote.remote-ssh
        ms-python.python
        charliermarsh.ruff
        mkhl.direnv
        zxh404.vscode-proto3
        humao.rest-client
        saoudrizwan.claude-dev
        ms-vscode.makefile-tools
        github.vscode-github-actions
        github.codespaces
        kamadorueda.alejandra
      ];
    };
  };
}
