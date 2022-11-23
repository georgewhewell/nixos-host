{ config, pkgs, lib, ... }: {

  imports = [
    ./development.nix
    # vscode-server.homeManagerModule
    # "${fetchTarball
    # "https://github.com/msteen/nixos-vscode-server/tarball/d2343b5eb47b811856085f3eff4d899a32b2c136"}/modules/vscode-server/home.nix"
  ];

  # services.vscode-server = {
  #   enable = true;
  #   # useFhsNodeEnvironment = false;
  # };
}
