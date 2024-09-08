{ config, pkgs, inputs, ... }:

{

  home.packages = with pkgs; [
    kitty
    alacritty
    grimblast
    rofi
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    # package = pkgs.hyprland.override ({
    #   wlroots = null;
    # });
    plugins = [
      # hyprland-plugins.packages.${pkgs.system}.hyprbars
    ];

    settings = {
      # monitor = ",highrr,auto,1";
      monitor = "DVI-I-1,3840x2160@60.00Hz,auto,1";
      "$mod" = "ALT";
      bind =
        [
          "mod SHIFT, Q, exec, exit"
          "$mod, F, exec, firefox"
          "$mod, T, exec, alacritty"
          "$mod, D, exec, rofi -show combi"
          "$mod, Enter, exec, alacritty"
          ", Print, exec, grimblast copy area"
        ]
        ++ (
          # workspaces
          # binds $mod + [shift +] {1..10} to [move to] workspace {1..10}
          builtins.concatLists (builtins.genList
            (
              x:
              let
                ws =
                  let
                    c = (x + 1) / 10;
                  in
                  builtins.toString (x + 1 - (c * 10));
              in
              [
                "$mod, ${ws}, workspace, ${toString (x + 1)}"
                "$mod SHIFT, ${ws}, movetoworkspace, ${toString (x + 1)}"
              ]
            )
            10)
        );
    };

  };
}
