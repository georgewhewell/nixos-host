{pkgs, network, ...}: {
  home.packages = with pkgs; [
    nixd
    nil
    alejandra
  ];

  programs.zed-editor = {
    enable = true;
    extensions = [
      "html"
      "toml"
      "nix"
      "ron"
      "git-firefly"
      "sql"
      "rust"
      "proto"
      "graphql"
      "lua"
      "dockerfile"
      "make"
      "terraform"
      "andromeda"
    ];
    userSettings = {
      current_line_highlight = "gutter";
      lsp = {
        rust-analyzer = {
          binary = {
          };
          enable_lsp_tasks = true;
        };
        nil = {
          initialization_options = {
            formatting = {
              command = ["alejandra"];
            };
            nix = {
              flake = {
                autoArchive = true;
                autoEvalInputs = true;
              };
            };
          };
        };
      };
      telemetry = {
        metrics = false;
      };
      vim_mode = false;
      ui_font_size = 18;
      buffer_font_size = 14;
      # ui_font_size = 14;
      # buffer_font_size = 11;
      theme = "Black Rain (blur)";
      ssh_connections = [
        {
          host = network.publicFqdn "trex";
        }
      ];
      language_models = {
        anthropic = {};
        google = {};
        lmstudio = {};
        openai = {};
      };
      languages = {
        Nix = {
          language_servers = [
            "nil"
            "!nixd"
          ];
          formatter = {
            external = {
              command = "alejandra";
            };
          };
        };
      };
    };
    userKeymaps = [
      {
        bindings = {
          up = "menu::SelectPrev";
        };
      }
      {
        context = "Editor";
        bindings = {
          escape = "editor::Cancel";
        };
      }
    ];
  };
}
