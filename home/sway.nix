{ config, lib, pkgs, ... }:

{

  imports = [
    ./waybar.nix
  ];

  home.packages = with pkgs; [
    slurp
    grim
    waypipe
  ];

  wayland.windowManager.sway = {
    enable = true;
    systemdIntegration = true;
    config = rec {
      bars = [ ];
      modifier = "Mod1";
      menu = "${pkgs.rofi}/bin/rofi -show combi";
      terminal = "${pkgs.alacritty}/bin/alacritty";
      keybindings =
        let
          pactl = "${pkgs.pulseaudioLight}/bin/pactl";
          playerctl = "${pkgs.playerctl}/bin/playerctl";
        in
        lib.mkOptionDefault {
          "${modifier}+Shift+s" = "exec loginctl lock-session $XDG_SESSION_ID";
          "${modifier}+Shift+p" = "exec slurp | grim -g -";

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

        # yoga touchpad
        "2:7:SynPS/2_Synaptics_TouchPad" = {
          dwt = "enabled";
          tap = "enabled";
          natural_scroll = "enabled";
          middle_emulation = "enabled";
        };
      };
      output = {
        "*" = { scale = "1"; };
        "DP-1" = { mode = "5120x1440@239.761002Hz"; };
        "Virtual-1" = { resolution = "1920x1200"; };
      };
      startup = [
        { command = "systemctl --user import-environment SWAYSOCK"; always = false; }
        { command = "systemctl --user restart waybar"; always = true; }
        { command = ''
            swayidle \
              timeout 300 'swaymsg "output * dpms off"' \
              resume 'swaymsg "output * dpms on"'
          '';
          always = false;
        }

        # static workspaces
        {
          command = ''
            swaymsg "workspace 9; exec alacritty --working-directory /etc/nixos -e sh -c 'while true; do vim .; done'; workspace 1"
          '';
          always = false;
        }
        {
          command = ''
            swaymsg "workspace 8; exec spotify; workspace 1"
          '';
          always = false;
        }
      ]
      ++ lib.optionals (config.hostId == "yoga") [ ];
    };
    extraConfig = ''
      # Styling
      default_border none

      # lock inhibitors
      for_window [app_id="firefox"] inhibit_idle fullscreen
    '';
  };
}
