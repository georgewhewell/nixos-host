{pkgs, ...}: {
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
    ];
    userSettings = {
      current_line_highlight = "gutter";
      features = {};
      lsp = {
        rust-analyzer = {
          binary = {
          };
        };
        nix = {
          binary = {
          };
        };
        nil = {
          initialization_options = {
            formatting = {
              command = ["alejandra"];
            };
          };
        };
      };
      telemetry = {
        metrics = false;
      };
      vim_mode = false;
      ui_font_size = 14;
      buffer_font_size = 11;
      theme = {
        mode = "system";
        light = "Ayu Light";
        dark = "Ayu Dark";
      };
      ssh_connections = [
        {
          host = "trex.satanic.link";
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
