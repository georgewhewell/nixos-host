{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };

  home.packages = with pkgs;
    [
      # for vscode-server..
      openssl
      pkg-config

      # platforms
      gh
      doctl

      # go tooling
      go
      gopls

      # rust tooling
      rustup

      # saas crap
      runpodctl

      # robot stuff
      aider-chat
      # claude-code
      # goose-cli

      # fml
      nodejs
    ]
    ++ lib.optionals (pkgs.system == "x86_64-linux") [
      # evm tooling
      # solc
      # foundry-bin
    ];

  home.sessionVariables = {
    OLLAMA_API_BASE = "http://localhost:11434";
  };
}
