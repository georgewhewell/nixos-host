{ config, lib, pkgs, ... }:

{
  programs.vim = {
    enable = true;
    plugins = [ 
      "vim-airline"
      "editorconfig-vim"
      "vim-nix"
      "rust-vim"
      # "LanguageClient"
      "fzf-vim"
      "gitgutter"
      "ale"
    ];
    settings = { ignorecase = true; };
    extraConfig = ''
      set mouse=a
      set laststatus=2
      set noshowmode

      let g:rustfmt_autosave = 1
      let g:racer_cmd = "/run/current-system/sw/bin/racer"
    '';

  };

}
