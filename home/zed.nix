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
    ];
    userSettings = {
      format_on_save = true;
      features = {
        copilot = true;
        inline_completion_provider = "ollama";
      };
      assistant = {
        version = "2";
        default_open_ai_model = null;
        default_model = {
          provider = "ollama";
          model = "deepseek-r1:70b";
        };
        inline_alternatives = [
          {
            provider = "copilot_chat";
            model = "o1-preview";
          }
        ];
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
        anthropic = {
          available_models = [
            {
              name = "claude-3-5-sonnet-latest";
              display_name = "claude-3-5-sonnet-latest";
              max_tokens = 128000;
              max_output_tokens = 2560;
              cache_configuration = {
                max_cache_anchors = 10;
                min_total_token = 10000;
                should_speculate = false;
              };
              # tool_override = "some-model-that-supports-toolcalling";
            }
          ];
        };
        google = {
          available_models = [
            {
              name = "gemini-1.5-flash-latest";
              display_name = "Gemini 1.5 Flash (Latest)";
              max_tokens = 1000000;
            }
          ];
        };
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
