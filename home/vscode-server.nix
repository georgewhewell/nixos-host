{ config, pkgs, lib, inputs, ... }: {

  imports = [
    ./development.nix
    inputs.vscode-server.homeModules.default
  ];

  services.vscode-server = {
    enable = true;
  };
}
