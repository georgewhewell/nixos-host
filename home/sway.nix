{ config, lib, pkgs, ... }:

{

  imports = [
    ./waybar.nix
  ];

  home.sessionVariables = {
    MOZ_DBUS_REMOTE = 1;
    MOZ_USE_XINPUT2 = 1;
    _JAVA_OPTIONS = "-Dawt.useSystemAAFontSettings=on -Dswing.aatext=true -Dsun.java2d.xrender=true";
  };

  home.packages = with pkgs; [
    alacritty
    slurp
    grim
    waypipe
  ];

  services.gammastep = {
    enable = true;
    provider = "manual";
    dawnTime = "6:00-7:45";
    duskTime = "18:35-20:15";
    tray = true;
    settings = {
      general = {
        adjustment-method = "wayland";
        gamma = 0.8;
      };
    };
  };

  services.mako =
    let
      homeIcons = "${config.home.homeDirectory}/.nix-profile/share/icons/hicolor";
      homePixmaps = "${config.home.homeDirectory}/.nix-profile/share/pixmaps";
      systemIcons = "/run/current-system/sw/share/icons/hicolor";
      systemPixmaps = "/run/current-system/sw/share/pixmaps";
    in
    {
      enable = true;
      backgroundColor = "#0A0E14";
      borderColor = "#53BDFA";
      defaultTimeout = 30 * 1000; # millis
      font = "monospace 10";
      iconPath = "${homeIcons}:${systemIcons}:${homePixmaps}:${systemPixmaps}";
      icons = true;
      maxIconSize = 96;
      maxVisible = 3;
      sort = "-time";
      textColor = "#B3B1AD";
      width = 500;
    };

  wayland.windowManager.sway = {
    enable = true;
    systemdIntegration = true;
    extraSessionCommands = ''
      . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"
    '';
    config = rec {
      bars = [ ];
      modifier = "Mod1";
      menu = "${pkgs.rofi}/bin/rofi -show combi";
      terminal = "${pkgs.alacritty}/bin/alacritty";
      keybindings =
        let
          pactl = "${pkgs.pulseaudio}/bin/pactl";
          playerctl = "${pkgs.playerctl}/bin/playerctl";
        in
        lib.mkOptionDefault {
          "${modifier}+Shift+s" = "exec loginctl lock-session $XDG_SESSION_ID";
          "${modifier}+Shift+p" = "exec slurp | grim -g -";
          "${modifier}+Pause" = "mode passthrough";

          # audio keys
          XF86AudioMute = "exec ${pactl} set-sink-mute 0 toggle";
          XF86AudioLowerVolume = "exec ${pactl} set-sink-volume 0 -5%";
          XF86AudioRaiseVolume = "exec ${pactl} set-sink-volume 0 +5%";
          XF86AudioMicMute = "exec ${pactl} set-source-mute 0 toggle";

          # media keys
          XF86AudioPlay = "exec ${playerctl} play-pause";
          XF86AudioPause = "exec ${playerctl} play-pause";
          XF86AudioNext = "exec ${playerctl} next";
          XF86AudioPrev = "exec ${playerctl} previous";
        };
      input = {
        # shared keyboard opts
        "*" = {
          xkb_layout = "gb";
          xkb_options = "caps:escape";
          repeat_rate = "35";
          repeat_delay = "190";
        };

        "1133:49983:Logitech_G815_RGB_MECHANICAL_GAMING_KEYBOARD" = {
          xkb_layout = "us";
        };

        # "1133:49983:Logitech_G815_RGB_MECHANICAL_GAMING_KEYBOARD" = {
        #   xkb_layout = "us";
        # };

        # yoga touchpad
        "2:7:SynPS/2_Synaptics_TouchPad" = {
          dwt = "enabled";
          tap = "enabled";
          natural_scroll = "enabled";
          middle_emulation = "enabled";
        };
      };
      output = {
        "eDP-1" = { scale = "1"; };
        "DP-1" = { mode = "5120x1440@59.977Hz"; };
      };
      startup = [
        { command = "${pkgs.mako}/bin/mako"; always = true; }
        {
          command = ''
            ${pkgs.swayidle}/bin/swayidle \
              timeout 600 "${pkgs.swaylock-effects}/bin/swaylock \
              --screenshots \
              --clock \
              --indicator \
              --indicator-radius 100 \
              --indicator-thickness 7 \
              --effect-blur 7x5 \
              --effect-vignette 0.5:0.5 \
              --ring-color bb00cc \
              --key-hl-color 880033 \
              --line-color 00000000 \
              --inside-color 00000088 \
              --separator-color 00000000 \
              --grace 30 \
              --fade-in 0.2" \
              timeout 3600 'swaymsg "output * dpms off"' \
              resume 'swaymsg "output * dpms on"' 
          '';
          always = false;
        }
        # static workspaces
        /*{
          command = ''
          swaymsg "workspace 9; exec alacritty --working-directory /etc/nixos -e sh -c 'while true; do vim .; done'; workspace 1"
          '';
          always = false;
          }*/
      ]
      ++ lib.optionals (config.hostId == "yoga") [ ]
      ++ lib.optionals (config.hostId == "workvm") [{
        command = ''
          ${pkgs.wayvnc}/bin/wayvnc 0.0.0.0
        '';
        always = false;
      }];
      modes = {
        passthrough = {
          "Mod1+Pause" = "mode default";
        };
        resize = {
          "h" = "resize shrink width 10 px";
          "j" = "resize grow height 10 px";
          "k" = "resize shrink height 10 px";
          "l" = "resize grow width 10 px";
          "Left" = "resize shrink width 10 px";
          "Down" = "resize grow height 10 px";
          "Up" = "resize shrink height 10 px";
          "Right" = "resize grow width 10 px";
          "Escape" = "mode default";
          "Return" = "mode default";
        };
      };
    };
    extraConfig = ''
      # Styling
      default_border none

      # lock inhibitors
      for_window [app_id="firefox"] inhibit_idle fullscreen
      for_window [app_id="Firefox"] inhibit_idle fullscreen
      for_window [class="dota2"] inhibit_idle fullscreen
    '';
  };
}
