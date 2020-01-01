{ pkgs, ... }:

let
  oled-brightness = pkgs.callPackage ./oled-brightness.nix { };
in {

  programs.feh.enable = true;
  programs.firefox = {
    enable = true;
    enableGoogleTalk = true;
  };

  home.packages = with pkgs; [
    corefonts
    dejavu_fonts
    ubuntu_font_family
    hack-font
    roboto
    powerline-fonts
    font-awesome-ttf
    source-code-pro
    source-sans-pro
    source-serif-pro
    font-awesome_5

    spotify
  ];

  fonts.fontconfig.enable = pkgs.lib.mkForce true;

  xsession = {
    enable = true;

    pointerCursor = {
      package = pkgs.vanilla-dmz;
      name = "Vanilla-DMZ";
      size = 64;
    };

    windowManager.i3 = rec {
      enable = true;
      config = {
        modifier = "Mod1";
        bars = [];
        keybindings = let
          mod = config.modifier;
        in {
          "${mod}+Return" = "exec alacritty";
          "${mod}+d" = "exec rofi -show run";
          "${mod}+Shift+q" = "kill";

          /* "${mod}+Shift+grave" = "move scratchpad";
          "${mod}+grave" = "scratchpad show"; */
          "${mod}+j" = "focus left";
          "${mod}+k" = "focus down";
          "${mod}+l" = "focus up";
          "${mod}+semicolon" = "focus right";

          "${mod}+Shift+j" = "move left";
          "${mod}+Shift+k" = "move down";
          "${mod}+Shift+l" = "move up";
          "${mod}+Shift+semicolon" = "move right";

          "${mod}+h" = "split h";
          "${mod}+v" = "split v";
          "${mod}+f" = "fullscreen";
          "${mod}+Shift+s" = "layout stacking";
          "${mod}+Shift+t" = "layout tabbed";
          "${mod}+Shift+f" = "floating toggle";
          "${mod}+space" = "focus mode_toggle";
          "${mod}+1" = "workspace 1";
          "${mod}+2" = "workspace 2";
          "${mod}+3" = "workspace 3";
          "${mod}+4" = "workspace 4";
          "${mod}+5" = "workspace 5";
          "${mod}+6" = "workspace 6";
          "${mod}+7" = "workspace 7";
          "${mod}+8" = "workspace 8";
          "${mod}+9" = "workspace 9";
          "${mod}+0" = "workspace 10";
          "${mod}+Shift+1" = "move container to workspace 1";
          "${mod}+Shift+2" = "move container to workspace 2";
          "${mod}+Shift+3" = "move container to workspace 3";
          "${mod}+Shift+4" = "move container to workspace 4";
          "${mod}+Shift+5" = "move container to workspace 5";
          "${mod}+Shift+6" = "move container to workspace 6";
          "${mod}+Shift+7" = "move container to workspace 7";
          "${mod}+Shift+8" = "move container to workspace 8";
          "${mod}+Shift+9" = "move container to workspace 9";
          "${mod}+Shift+0" = "move container to workspace 10";
          "${mod}+Shift+r" = "restart";
          "${mod}+Shift+e" = "exec \"i3-nagbar -t warning -m 'You pressed the exit shortcut. Do you really want to exit i3? This will end your X session.' -b 'Yes, exit i3' 'i3-msg exit'\"";
          "${mod}+r" = "mode resize";

          "XF86AudioRaiseVolume" = "exec ${pkgs.pulseaudioLight}/bin/pactl set-sink-volume 0 +5%";
          "XF86AudioLowerVolume" = "exec ${pkgs.pulseaudioLight}/bin/pactl set-sink-volume 0 -5%";
          "XF86AudioMute" = "exec ${pkgs.pulseaudioLight}/bin/pactl set-sink-mute 0 toggle";
          "XF86AudioMicMute" = "exec ${pkgs.pulseaudioLight}/bin/pactl set-source-mute 0 toggle";

          "XF86MonBrightnessUp" = "exec ${oled-brightness}/bin/oled-brightness up";
          "XF86MonBrightnessDown" = "exec ${oled-brightness}/bin/oled-brightness";

          "XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play";
          "XF86AudioPause" = "exec ${pkgs.playerctl}/bin/playerctl pause";
          "XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
          "XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";
        };
        startup = [
          { command = "systemctl --user restart polybar"; always = true; notification = false; }
          { command = "feh --bg-fill ${./backgrounds/home.jpg}"; always = true; notification = false; }
        ];
      };
      extraConfig = ''
        # No title/border
        for_window [class="^.*"] border pixel 0
      '';
    };
  };

}
