{ config, pkgs, ... }:

{
  programs.kitty = {
    enable = true;

    settings = {
      font_size = if config.hostId == "yoga" then 13 else 11;
      scrollback_lines = 10000;
      window_padding_width = 0;
      hide_window_decorations = true;

      # Enable primary selection for middle-click paste between apps
      copy_on_select = "yes";
      clipboard_control = "write-clipboard read-clipboard write-primary read-primary";

      # Colors (Hyper)
      foreground = "#ffffff";
      background = "#000000";
      cursor = "#ffffff";
      cursor_text_color = "#F81CE5";

      # Normal colors
      color0 = "#000000";
      color1 = "#fe0100";
      color2 = "#33ff00";
      color3 = "#feff00";
      color4 = "#0066ff";
      color5 = "#cc00ff";
      color6 = "#00ffff";
      color7 = "#d0d0d0";

      # Bright colors
      color8 = "#808080";
      color9 = "#fe0100";
      color10 = "#33ff00";
      color11 = "#feff00";
      color12 = "#0066ff";
      color13 = "#cc00ff";
      color14 = "#00ffff";
      color15 = "#ffffff";
    };
  };
}
