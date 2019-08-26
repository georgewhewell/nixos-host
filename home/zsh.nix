{ config, lib, pkgs, ... }:

{

  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;

    initExtra = ''
      # bindkey -e

      # prezto
      source ${pkgs.zsh-prezto}/runcoms/zshrc

      # make nix-shell use zsh
      ${pkgs.any-nix-shell}/bin/any-nix-shell zsh --info-right | source /dev/stdin
    '';

    shellAliases = {
      ll = "exa -la";
    };
  };

}
