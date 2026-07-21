{
  lib,
  pkgs,
  ...
}: {
  home = {
    packages = with pkgs;
      [
        nixpkgs-fmt
        statix

        # Lua
        stylua
        (luajit.withPackages (p: with p; [luacheck]))
        lua-language-server

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
      ]
      ++ lib.optionals (pkgs.stdenv.isLinux) [
        pre-commit
      ];
  };

  programs = {
    git.settings.core.editor = "nvim";

    neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      withRuby = false;
      withPython3 = false;

      initLua = ''
        -- Disable mouse so terminal copy/paste works
        vim.opt.mouse = ""

        -- Make inlay hints more visible
        vim.api.nvim_set_hl(0, 'LspInlayHint', { fg = '#808080', bg = '#2a2a2a', italic = true })

        -- Show diagnostics inline as virtual text
        vim.diagnostic.config({
          virtual_text = {
            spacing = 4,
            prefix = '●',
          },
          float = {
            source = 'always',
            border = 'rounded',
          },
          signs = true,
          underline = true,
          update_in_insert = false,
          severity_sort = true,
        })

        -- Auto-show diagnostic float on cursor hold
        vim.api.nvim_create_autocmd('CursorHold', {
          callback = function()
            vim.diagnostic.open_float(nil, { focusable = false })
          end,
        })

        -- Reduce the delay before CursorHold triggers
        vim.opt.updatetime = 500

        -- Trouble.nvim setup
        require('trouble').setup({})

        -- nvim-cmp setup for completions
        local cmp = require('cmp')
        cmp.setup({
          snippet = {
            expand = function(args)
              require('luasnip').lsp_expand(args.body)
            end,
          },
          mapping = cmp.mapping.preset.insert({
            ['<C-Space>'] = cmp.mapping.complete(),
            ['<CR>'] = cmp.mapping.confirm({ select = true }),
          }),
          sources = {
            { name = 'nvim_lsp' },
            { name = 'buffer' },
          },
        })

        -- LSP setup using new vim.lsp.config API
        vim.lsp.config['rust-analyzer'] = {
          cmd = { 'rust-analyzer' },
          filetypes = { 'rust' },
          root_markers = { 'Cargo.toml', 'rust-project.json' },
          settings = {
            ['rust-analyzer'] = {
              inlayHints = {
                enable = true,
                chainingHints = { enable = true },
                parameterHints = { enable = true },
                typeHints = { enable = true },
              },
            },
          },
        }

        -- Auto-enable rust-analyzer for rust files
        vim.api.nvim_create_autocmd('FileType', {
          pattern = 'rust',
          callback = function()
            vim.lsp.enable('rust-analyzer')
          end,
        })

        -- Enable for buffer opened at startup
        vim.api.nvim_create_autocmd('VimEnter', {
          callback = function()
            if vim.bo.filetype == 'rust' then
              vim.lsp.enable('rust-analyzer')
            end
          end,
        })

        -- Enable inlay hints when LSP attaches
        vim.api.nvim_create_autocmd('LspAttach', {
          callback = function(args)
            local client = vim.lsp.get_client_by_id(args.data.client_id)
            if client and client.server_capabilities.inlayHintProvider then
              vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
            end
          end,
        })
      '';

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
          (nvim-treesitter.withPlugins (p: [
            p.rust
            p.nix
            p.lua
            p.toml
            p.json
            p.markdown
            p.bash
          ]))
          nvim-treesitter-context
          nvim-web-devicons
          stabilize-nvim
          todo-comments-nvim
          trouble-nvim
          true-zen-nvim

          # tooling
          nvim-bufdel
          # vim-plugins
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
          none-ls-nvim
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

          # rust
          rust-vim
        ]
        ++ lib.optional (lib.elem pkgs.stdenv.hostPlatform.system pkgs.tabnine.meta.platforms) cmp-tabnine;
    };
  };
}
