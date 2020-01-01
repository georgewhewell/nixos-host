{ config, lib, pkgs, ... }:

{

  programs.vim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [
      vim-airline
      editorconfig-vim
      vim-nix
      rust-vim
      fzf-vim
      gitgutter
      ale

      denite
      denite-extra
    ];
    settings = { ignorecase = true; };
    extraConfig = ''
      set mouse=a
      set laststatus=2
      set noshowmode
      set number

      let g:rustfmt_autosave = 1
      let g:racer_cmd = "/run/current-system/sw/bin/racer"
    '';

  };

}
