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
        size = if config.hostId == "yoga" then 18 else 10;
        use_thin_strokes = false;
      };

      mouse_bindings = [
        { mouse = "Middle"; action = "PasteSelection"; }
      ];

    };

  };
}
