{ config, lib, pkgs, ... }:

{
  programs.starship = {
    enable = true;
    settings = {
      aws.disabled = true;
      gcloud.disabled = true;
    };
  };

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
      pc = "pycharm-community . > /dev/null 2>&1 &";
    };

    # prezto = {
    #   enable = true;
    #   pmodules = [
    #     "environment"
    #     "terminal"
    #     "editor"
    #     "history"
    #     "directory"
    #     "spectrum"
    #     "utility"
    #     "completion"
    #     "prompt"
    #     "git"
    #     "gpg"
    #   ];
    #   prompt = {
    #     theme = "paradox";
    #   };
    #   utility.safeOps = false;
    # };
  };

}
