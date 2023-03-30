{ config, pkgs, lib, ... }: {

  imports = [
    ./development.nix
    # pkgs.vscode-server-src

    "${fetchTarball {
      url = "https://github.com/msteen/nixos-vscode-server/tarball/options";
      sha256 = "sha256:1nf571y53v813s8rdawj1limgjqh13i0x2n0h69n2jzhwq9mhdql";
    }}/modules/vscode-server/home.nix"
  ];

  services.vscode-server = {
    enable = true;
    #useFhsNodeEnvironment = false;
  };
}



