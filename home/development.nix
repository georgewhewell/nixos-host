{ config, lib, pkgs, ... }: {

  home.packages = with pkgs; [
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
    (rust-bin.beta.latest.default.override
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
