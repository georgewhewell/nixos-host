{ config, pkgs, ... }:

{

  programs.alacritty = {
    enable = true;
    settings = {

      window = {
        decorations = "none";
        dynamic_padding = false;
        padding = {
          columns = 0;
          lines = 0;
        };

      };

      scrolling = {
        history = 10000;
      };

      font = {
        size = if config.hostId == "yoga" then 18 else 12;
      };

      mouse_bindings = [
        { mouse = "Middle"; action = "PasteSelection"; }
      ];


      # Colors (Hyper)
      colors = {
        # Default colors
        primary = {
          background = "0x000000";
          foreground = "0xffffff";
        };
        cursor = {
          text = "0xF81CE5";
          cursor = "0xffffff";
        };

        # Normal colors
        normal = {
          black = "0x000000";
          red = "0xfe0100";
          green = "0x33ff00";
          yellow = "0xfeff00";
          blue = "0x0066ff";
          magenta = "0xcc00ff";
          cyan = "0x00ffff";
          white = "0xd0d0d0";
        };
        # Bright colors
        bright = {
          black = "0x808080";
          red = "0xfe0100";
          green = "0x33ff00";
          yellow = "0xfeff00";
          blue = "0x0066ff";
          magenta = "0xcc00ff";
          cyan = "0x00ffff";
          white = "0xFFFFFF";
        };
      };
    };
  };
}
