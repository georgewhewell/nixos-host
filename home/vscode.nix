{ config, pkgs, lib, ... }: {

  imports = [ ./development.nix ];

  programs.vscode = {
    package = pkgs.vscode;
    enable = true;
    mutableExtensionsDir = true;
    userSettings = {
      "update.mode" = "none";
      "extensions.autoUpdate" = false;
      "explorer.confirmDelete" = false;
      "workbench.colorTheme" = "Pitch Black";
      "editor.formatOnSave" = true;
      "editor.formatOnType" = true;
      "rust-analyzer.runnables.command" = "/etc/profiles/per-user/grw/bin/cargo";
      "rust-analyzer.server.path" = "/etc/profiles/per-user/grw/bin/rust-analyzer";
      "[rust]" = {
        "editor.defaultFormatter" = "rust-lang.rust-analyzer";
        "editor.formatOnSave" = true;
      };
      "remote.SSH.enableX11Forwarding" = false;
    };
    extensions = with pkgs.vscode-extensions; [
      jnoortheen.nix-ide
      golang.go
      # ms-python.python
      # ms-python.vscode-pylance
      hashicorp.terraform
      viktorqvarfordt.vscode-pitch-black-theme
      rust-lang.rust-analyzer
      ms-vscode-remote.remote-ssh
      ms-vsliveshare.vsliveshare
      tamasfe.even-better-toml
      mkhl.direnv
      github.copilot

      (pkgs.vscode-utils.buildVscodeMarketplaceExtension {
        mktplcRef = {
          publisher = "JuanBlanco";
          name = "solidity";
          version = "0.0.141";
          sha256 = "sha256-UWdjVY6+TyIRuIxru4+4YGqqI0HUU/8yV8BKNlIRIUQ=";
        };
      })
    ];
  };

}
