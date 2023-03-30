{ config, pkgs, lib, ... }: {

  imports = [ ./development.nix ];

  programs.vscode = {
    enable = true;
    mutableExtensionsDir = true;
    userSettings = {
      "update.mode" = "none";
      "extensions.autoUpdate" = false;
      "explorer.confirmDelete" = false;
      "workbench.colorTheme" = "Pitch Black";
      "editor.formatOnSave" = true;
      "editor.formatOnType" = true;
      "editor.inlineSuggest.enabled" = true;
      "rust-analyzer.runnables.command" = "/etc/profiles/per-user/grw/bin/cargo";
      "[rust]" = {
        "editor.defaultFormatter" = "rust-lang.rust-analyzer";
        "editor.formatOnSave" = true;
      };
      "github.copilot-labs.advanced" = {
        showTestGenerationLenses = true;
        showBrushesLenses = true;
      };
      "remote.SSH.enableX11Forwarding" = false;
    };
    extensions = with pkgs.vscode-extensions; [
      jnoortheen.nix-ide
      golang.go
      hashicorp.terraform
      viktorqvarfordt.vscode-pitch-black-theme
      rust-lang.rust-analyzer
      ms-vscode-remote.remote-ssh
      # ms-vsliveshare.vsliveshare
      tamasfe.even-better-toml
      mkhl.direnv

      (pkgs.vscode-utils.buildVscodeMarketplaceExtension {
        mktplcRef = {
          publisher = "GitHub";
          name = "copilot";
          version = "1.73.8685";
          sha256 = "sha256-W1j1VAuSM1sgxHRIahqVncUlknT+MPi7uutY+0NURZQ=";
        };
      })

      (pkgs.vscode-utils.buildVscodeMarketplaceExtension {
        mktplcRef = {
          publisher = "GitHub";
          name = "copilot-labs";
          version = "0.10.704";
          sha256 = "sha256-PFAfTAIZ/OMQdZhN5yekllR/QNxbPvNgrLmHmRaDUvY=";
        };
      })

      (pkgs.vscode-utils.buildVscodeMarketplaceExtension {
        mktplcRef = {
          publisher = "JuanBlanco";
          name = "solidity";
          version = "0.0.141";
          sha256 = "sha256-UWdjVY6+TyIRuIxru4+4YGqqI0HUU/8yV8BKNlIRIUQ=";
        };
      })

      (pkgs.vscode-utils.buildVscodeMarketplaceExtension {
        mktplcRef = {
          publisher = "starkware";
          name = "cairo";
          version = "0.10.0";
          sha256 = "sha256-Jpj6QSLvYI3FbSW07PDlhVj9Gv0ZUrMbK+KVFvmBMvE=";
        };
      })
    ];
  };

}
