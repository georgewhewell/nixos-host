{ config, lib, pkgs, ... }:

{
  xdg.configFile."nvim/lua".source = ./lua;

  home = {
    # packages = with pkgs; [ neovim ];
    sessionVariables = rec {
      EDITOR = "nvim";
      VISUAL = EDITOR;
    };
  };

  programs = {
    git.extraConfig = {
      core.editor = "nvim";
      merge.tool = "nvimdiff";
      "mergetool \"nvimdiff\"".cmd = "nvim -d $LOCAL $REMOTE";
      diff.tool = "nvimdiff";
    };
    zsh.shellAliases = { vi = "nvim"; vim = "nvim"; };

    neovim = {
      enable = true;
      extraPackages = with pkgs; [ nodejs rnix-lsp ];
      extraConfig = "lua require('init')";
      plugins = with pkgs.vimPlugins; [
        # ui
        bufferline-nvim
        feline-nvim
        gitsigns-nvim
        indent-blankline-nvim
        lsp-colors-nvim
        lsp_signature-nvim
        neovim-ayu
        numb-nvim
        nvim-gps
        nvim-lightbulb
        nvim-treesitter-context
        nvim-web-devicons
        stabilize-nvim
        todo-comments-nvim
        trouble-nvim

        # tooling
        nvim-bufdel
        rust-tools-nvim
        suda-vim
        tabular
        telescope-frecency-nvim
        telescope-nvim
        vim-better-whitespace
        vim-commentary
        vim-fugitive
        vim-gist
        vim-rhubarb
        vim-sleuth
        vim-surround
        vim-visual-multi

        # completion
        cmp-buffer
        cmp-cmdline
        cmp-latex-symbols
        cmp-nvim-lsp
        cmp-nvim-lua
        cmp-path
        cmp-treesitter
        cmp_luasnip
        crates-nvim
        lspkind-nvim
        luasnip
        nvim-autopairs
        nvim-cmp
        nvim-lspconfig
        snippets-nvim

        # syntax
        (nvim-treesitter.withPlugins
          (_:
            with builtins;
            filter
              (drv:
                !elem
                  drv.pname
                  (map (v: "tree-sitter-${v}-grammar") [
                    "agda"
                    "fluent"
                    "kotlin"
                    "markdown"
                    "supercollider"
                    "swift"
                    "verilog"
                  ])
              )
              pkgs.tree-sitter.allGrammars
          )
        )
        nvim-treesitter-textobjects
        editorconfig-vim
        gentoo-syntax
        lalrpop-vim
        vim-nix
        vim-polyglot
      ] ++ lib.optionals (pkgs.hostPlatform.system == "x86_64-linux") [
        cmp-tabnine
      ];
    };
  };
}
