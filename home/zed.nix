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
      features = {
        copilot = true;
        # inline_completion_provider = "copilot";
        # edit_prediction_provider = "copilot";
      };
      assistant = {
        version = "2";
        default_model = {
          provider = "google";
          model = "gemini-2.5-pro-exp-03-25";
        };
      };
      lsp = {
        rust-analyzer = {
          binary = {
            path_lookup = true;
          };
        };
        nix = {
          binary = {
            path_lookup = true;
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
      ui_font_size = 12;
      buffer_font_size = 11;
      theme = {
        mode = "system";
        light = "Andromeda";
        dark = "One Dark";
      };
      ssh_connections = [
        {
          host = "trex.satanic.link";
        }
      ];
      language_models = {
        anthropic = {};
        google = {
          available_models = [
            {
              name = "gemini-2.5-pro-exp-03-25";
              display_name = "Gemini 2.5 Pro Exp";
              max_tokens = 1000000;
            }
          ];
        };
        lmstudio = {};
        ollama = {
          api_url = "http://localhost:11434";
          available_models = [
            {
              name = "qwen2.5-coder";
              display_name = "qwen 2.5 coder 32K";
              max_tokens = 32768;
            }
            {
              name = "deepseek-r1:70b";
              display_name = "deepseek r1 70b";
              max_tokens = 131072;
            }
          ];
        };
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
