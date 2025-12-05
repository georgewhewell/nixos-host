{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [./vim/default.nix];
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
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
    ])
    ++ (with inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}; [
      claude-code
      # claude-code-router
      gemini-cli
      # qwen-code
      #      opencode
      # nanocoder
      # codex
      # crush
    ])
    ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
      # evm tooling
      # solc
      # foundry-bin
    ];
}
