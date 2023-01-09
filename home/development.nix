{ config, lib, pkgs, ... }: {

  home.packages = with pkgs; [

    # for vscode-server..
    openssl
    pkg-config

    # platforms
    gh
    doctl

    # go tooling
    go
    gopls

    # evm tooling
    solc
    foundry-bin

    # rust tooling
    (rust-bin.nightly.latest.default.override
      {
        extensions = [
          "rust-src"
          "rustfmt"
          "rust-analyzer-preview"
        ];
      }
    )
  ];
}
