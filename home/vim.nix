{ config, lib, pkgs, ... }:

{

  home.packages = with pkgs; [
    fzf
    fd
  ];

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

      vim-test
      denite
      denite-extra
    ];
    settings = { ignorecase = true; };
    extraConfig = ''
      set mouse=a
      set laststatus=2
      set noshowmode
      set number

      nmap <silent> t<C-n> :TestNearest<CR>
      nmap <silent> t<C-f> :TestFile<CR>
      nmap <silent> t<C-s> :TestSuite<CR>
      nmap <silent> t<C-l> :TestLast<CR>
      nmap <silent> t<C-g> :TestVisit<CR>
      
      nnoremap <silent> <Space><Space> :Files<CR>

      let g:rustfmt_autosave = 1
      let g:racer_cmd = "/run/current-system/sw/bin/racer"
    '';

  };

}
