{ pkgs, ... }: {
  imports = [ ./development.nix ];

  home.packages = with pkgs; [
    nixpkgs-fmt
  ];

  programs.vscode = {
    enable = true;
    mutableExtensionsDir = false;
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
        "editor.defaultFormatter" = "rust-lang.rust-analyzer";
        "editor.formatOnSave" = true;
      };
      "[python]" = {
        "editor.defaultFormatter" = "charliermarsh.ruff";
      };
      "remote.SSH.enableX11Forwarding" = false;
      "ruff.nativeServer" = true;
    };
    extensions = with pkgs.vscode-extensions; [
      jnoortheen.nix-ide
      hashicorp.terraform
      viktorqvarfordt.vscode-pitch-black-theme
      github.copilot
      rust-lang.rust-analyzer
      ms-vscode-remote.remote-ssh
      ms-python.python
      charliermarsh.ruff
      mkhl.direnv
      zxh404.vscode-proto3
      humao.rest-client
      continue.continue
      saoudrizwan.claude-dev
    ];
  };
}
