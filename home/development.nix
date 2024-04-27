{ config, lib, pkgs, ... }: {

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
  };

  home.packages = with pkgs; [
    # nix deploy
    colmena

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
    #runpodctl
  ] ++ lib.optionals (pkgs.system == "x86_64-linux") [
    # evm tooling
    solc
    # foundry-bin
  ];

}
