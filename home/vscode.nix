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
      "rust-analyzer.checkOnSave.extraArgs" = [
        "--target-dir"
        "\${workspaceFolder}/target/check"
      ];
      "remote.SSH.enableX11Forwarding" = false;
    };
    extensions = with pkgs.vscode-extensions; [
      jnoortheen.nix-ide
      golang.go
      ms-python.python
      ms-python.vscode-pylance
      hashicorp.terraform
      viktorqvarfordt.vscode-pitch-black-theme
      rust-lang.rust-analyzer
      ms-vscode-remote.remote-ssh
      ms-vsliveshare.vsliveshare
      tamasfe.even-better-toml
      mkhl.direnv

      (pkgs.vscode-utils.buildVscodeMarketplaceExtension {
        mktplcRef = {
          publisher = "JuanBlanco";
          name = "solidity";
          version = "0.0.139";
          sha256 = "sha256-hEC6NlEsodWuR04UTyHWOdWc6S+0wsqSWqzCSs6VaB0=";
        };
      })
    ];
  };

}