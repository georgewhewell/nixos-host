{ config, pkgs, lib, ... }: {

  imports = [ ./development.nix ];

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
        "source.fixAll" = true;
        "source.organizeImports" = true;
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
      #golang.go
      hashicorp.terraform
      # viktorqvarfordt.vscode-pitch-black-theme
      github.copilot
      rust-lang.rust-analyzer
      ms-vscode-remote.remote-ssh
      ms-python.python
      charliermarsh.ruff
      # ms-vsliveshare.vsliveshare
      # tamasfe.even-better-toml
      mkhl.direnv
      # zxh404.vscode-proto3
      # humao.rest-client

      # (pkgs.vscode-utils.buildVscodeMarketplaceExtension {
      #   mktplcRef = {
      #     publisher = "JuanBlanco";
      #     name = "solidity";
      #     version = "0.0.141";
      #     sha256 = "sha256-UWdjVY6+TyIRuIxru4+4YGqqI0HUU/8yV8BKNlIRIUQ=";
      #   };
      # })

      # (pkgs.vscode-utils.buildVscodeMarketplaceExtension {
      #   mktplcRef = {
      #     publisher = "starkware";
      #     name = "cairo";
      #     version = "0.10.0";
      #     sha256 = "sha256-Jpj6QSLvYI3FbSW07PDlhVj9Gv0ZUrMbK+KVFvmBMvE=";
      #   };
      # })
    ];
  };

}
