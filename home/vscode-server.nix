{ config, pkgs, lib, inputs, ... }: {

  imports = [
    ./vscode.nix
    ./development.nix
    inputs.vscode-server.homeModules.default
  ];

  services.vscode-server = {
    enable = true;
  };
}
