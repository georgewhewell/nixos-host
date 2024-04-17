{ config, pkgs, inputs, ... }:

{

  imports = [
    # inputs.rose-pine-hyprcursor.nixosModules.${pkgs.system}.default
  ];

  home.packages = with pkgs;
    [
      kitty
      alacritty
      grimblast
      rofi
      inputs.rose-pine-hyprcursor.packages.${pkgs.system}.default
    ];

  wayland.windowManager.hyprland = {
    enable = true;
    plugins = [
      # hyprland-plugins.packages.${pkgs.system}.hyprbars
    ];

    settings = {
      # monitor = ",highrr,auto,1";
      monitor = ",highres,auto,1";
      env = "HYPRCURSOR_THEME,rose-pine-hyprcursor";
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
