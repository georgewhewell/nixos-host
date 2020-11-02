{ config, lib, pkgs, ... }:

{

  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;

    initExtra = ''
      # make nix-shell use zsh
      ${pkgs.any-nix-shell}/bin/any-nix-shell zsh --info-right | source /dev/stdin
    '';

    shellAliases = {
      ll = "exa -la";
      pyclean = "find . | grep -E '(__pycache__|\.pyc|\.pyo$)' | xargs rm -rf";
    };

    prezto = {
      enable = true;
      pmodules = [
        "environment"
        "terminal"
        "editor"
        "history"
        "directory"
        "spectrum"
        "utility"
        "completion"
        "prompt"
        "git"
      ];
      prompt = {
        theme = "paradox";
      };
      utility.safeOps = false;
    };
  };

}
