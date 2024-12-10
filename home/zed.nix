{ config, lib, pkgs, ... }:

{
  programs.zed-editor =
    let
      bins = with pkgs; [
        nixd
        nixfmt-rfc-style
        prettierd
        nodejs
        nodePackages.prettier
        vscode-langservers-extracted
      ];
      libraries = with pkgs; [
        stdenv.cc.cc
        zlib
        openssl
      ];
    in
    {
      enable = true;
      # package = with pkgs; writeShellScriptBin "zed" ''
      #   export PATH=${lib.makeBinPath bins}:$PATH
      #   export LD_LIBRARY_PATH=${lib.makeLibraryPath libraries}
      #   export NIX_LD_LIBRARY_PATH=${lib.makeLibraryPath libraries}
      #   export NIX_LD=${stdenv.cc.bintools.dynamicLinker}
      #   exec ${zed-editor}/bin/zed "$@"
      # '';
      userSettings = {
        features = {
          copilot = true;
          inline_completion_provider = "supermaven";
        };
        assistant = {
          version = "2";
          default_model = {
            provider = "anthropic";
            model = "claude-3-5-sonnet-latest";
          };
        };
        lsp = {
          rust-analyzer = {
            binary = { path_lookup = true; };
          };
        };
        telemetry = {
          metrics = false;
        };
        vim_mode = false;
        ui_font_size = 16;
        buffer_font_size = 16;
        theme = {
          mode = "system";
          light = "Andromeda";
          dark = "One Dark";
        };
      };
      userKeymaps = [
        { bindings = { up = "menu::SelectPrev"; }; }
        {
          context = "Editor";
          bindings = { escape = "editor::Cancel"; };
        }
      ];
    };

}
