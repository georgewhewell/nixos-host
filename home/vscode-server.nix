{ config, pkgs, lib, ... }: {

  imports = [
    ./development.nix
    (import "${pkgs.vscode-server-src}/modules/a").nixosModules.home
  ];

  services.vscode-server = {
    enable = true;
    # useFhsNodeEnvironment = false;
  };
}

