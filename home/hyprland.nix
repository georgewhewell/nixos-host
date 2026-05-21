{
  config,
  pkgs,
  inputs,
  ...
}: {
  home.packages = with pkgs; [
    grimblast
    rofi
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    plugins = [
    ];

    settings = {
      # Monitor config with HDR
      # Layout: [15" portrait] [Dell center] [16" portrait]
      # Using desc: for stable identification across reboots
      monitor = [
        "desc:Woodwind Communications Systems Inc SU15TO, 3840x2160@30, 0x418, 2, transform, 3" # 15" left portrait (270°)
        "desc:Dell Inc. AW3225QF, 3840x2160@120, 1080x0, 1, bitdepth, 10, cm, wide, sdrbrightness, 1.4" # Dell center (DCI-P3)
        "desc:Woodwind Communications Systems Inc AU16TO, 3840x2160@30, 4920x0, 2, transform, 3" # 16" right portrait (270°)
        "desc:DLOGIC Ltd. No Monitor, 3840x2160@30, 4920x0, 2, transform, 3" # 16" right portrait alt name (270°)
        ", preferred, auto, 1" # fallback for other monitors
      ];

      # Render settings for HDR/color management
      render = {
        cm_enabled = true;
        cm_fs_passthrough = true;
      };

      misc = {
        vrr = 1; # 0=off, 1=on, 2=fullscreen only
        vfr = true;
      };

      "$mod" = "ALT";

      bind =
        [
          "$mod SHIFT, Q, killactive"
          "$mod SHIFT, C, killactive"
          "$mod, F, exec, firefox"
          "$mod, T, exec, kitty"
          "$mod, D, exec, rofi -show combi"
          "$mod, Return, exec, kitty"
          ", Print, exec, grimblast copy area"

          # Split direction (like sway's $mod+v / $mod+b)
          "$mod, V, layoutmsg, preselect d"   # next window opens below (vertical split)
          "$mod, B, layoutmsg, preselect r"   # next window opens right (horizontal split)

          # Window management
          "$mod, H, movefocus, l"
          "$mod, L, movefocus, r"
          "$mod, K, movefocus, u"
          "$mod, J, movefocus, d"
          "$mod SHIFT, H, movewindow, l"
          "$mod SHIFT, L, movewindow, r"
          "$mod SHIFT, K, movewindow, u"
          "$mod SHIFT, J, movewindow, d"
          "$mod, Space, togglefloating"
          "$mod SHIFT, F, fullscreen"

          # Resize mode
          "$mod, R, submap, resize"

          # DPMS - turn off displays (wake on kb/mouse)
          "$mod SHIFT, P, exec, hyprctl dispatch dpms off"
        ]
        ++ (
          # workspaces
          # binds $mod + [shift +] {1..10} to [move to] workspace {1..10}
          builtins.concatLists (builtins.genList
            (
              x: let
                ws = let
                  c = (x + 1) / 10;
                in
                  builtins.toString (x + 1 - (c * 10));
              in [
                "$mod, ${ws}, workspace, ${toString (x + 1)}"
                "$mod SHIFT, ${ws}, movetoworkspace, ${toString (x + 1)}"
              ]
            )
            10)
        );

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      input = {
        kb_layout = "gb";
        kb_options = "caps:escape";
        repeat_rate = 35;
        repeat_delay = 190;
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
        "col.inactive_border" = "rgba(595959aa)";
      };

      decoration = {
        rounding = 10;
        blur = {
          enabled = true;
          size = 3;
          passes = 1;
        };
        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };
      };

      animations = {
        enabled = true;
        bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
        animation = [
          "windows, 1, 7, myBezier"
          "windowsOut, 1, 7, default, popin 80%"
          "border, 1, 10, default"
          "fade, 1, 7, default"
          "workspaces, 1, 6, default"
        ];
      };

      dwindle = {
        preserve_split = true;
        force_split = 0;
      };
    };

    extraConfig = ''
      # Resize submap
      submap = resize
      bind = , H, resizeactive, -10 0
      bind = , L, resizeactive, 10 0
      bind = , K, resizeactive, 0 -10
      bind = , J, resizeactive, 0 10
      bind = , Return, submap, reset
      bind = , Escape, submap, reset
      submap = reset
    '';
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = ""; # no lock screen for now
        before_sleep_cmd = "hyprctl dispatch dpms off";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 600; # 10 minutes
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };
}
