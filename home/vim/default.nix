{
  lib,
  pkgs,
  ...
}: {
  home = {
    sessionVariables = rec {
      EDITOR = "nvim";
      VISUAL = EDITOR;
    };
    shellAliases = {
      vi = "nvim";
      vim = "nvim";
    };
    packages = with pkgs; [
      nixpkgs-fmt
      statix

      # Lua
      stylua
      (luajit.withPackages (p: with p; [luacheck]))
      sumneko-lua-language-server

      # Shell
      shellcheck
      shfmt

      # GitHub Actions
      act
      actionlint
      python3Packages.pyflakes
      shellcheck

      # Misc
      jq
      rage
    ] ++ lib.optionals (pkgs.stdenv.isLinux) [
      pre-commit
    ];
  };

  programs = {
    git.extraConfig.core.editor = "nvim";

    neovim = {
      enable = true;

      plugins = with pkgs.vimPlugins;
        [
          # ui
          bufferline-nvim
          lualine-nvim
          gitsigns-nvim
          indent-blankline-nvim
          lsp-colors-nvim
          lsp_signature-nvim
          neovim-ayu
          numb-nvim
          nvim-lightbulb
          nvim-navic
          nvim-treesitter-context
          nvim-web-devicons
          stabilize-nvim
          todo-comments-nvim
          trouble-nvim
          true-zen-nvim

          # tooling
          nvim-bufdel
          rust-tools-nvim
          vim-suda
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
          vim-tmux-navigator
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
          null-ls-nvim
          lspkind-nvim
          luasnip
          nvim-autopairs
          nvim-cmp
          nvim-lspconfig
          snippets-nvim

          # syntax
          editorconfig-vim
          lalrpop-vim
          vim-nix
          vim-polyglot
        ]
        ++ lib.optional (lib.elem pkgs.hostPlatform.system pkgs.tabnine.meta.platforms) cmp-tabnine;
    };
  };

  # xdg.configFile."nvim/lua".source = ./lua;
  # xdg.configFile."nvim/init.lua".source = ./init.lua;
}
