{ pkgs, ... }:

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
        size = 6;
        use_thin_strokes = true;
      };

      mouse_bindings = [
        { mouse = "Middle"; action = "PasteSelection"; }
      ];

    };

  };
}
