{ config, pkgs, lib, ... }: {

  imports = [
    ./development.nix
    # pkgs.vscode-server-src

    "${fetchTarball {
      url = "https://github.com/msteen/nixos-vscode-server/tarball/master";
      sha256 = "sha256:1qga1cmpavyw90xap5kfz8i6yz85b0blkkwvl00sbaxqcgib2rvv";
    }}/modules/vscode-server/home.nix"
  ];

  services.vscode-server = {
    enable = true;
    # useFhsNodeEnvironment = false;
  };
}



