{ config, lib, pkgs, ... }:

{

  imports = [
    ./waybar.nix
  ];

  home.packages = with pkgs; [
    alacritty
    slurp
    grim
    waypipe
    swaylock-effects
  ];

  programs.mako = {
    enable = true;
    defaultTimeout = 15000;
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
          pactl = "${pkgs.pulseaudioLight}/bin/pactl";
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
        "DP-1" = { mode = "5120x1440@60Hz"; };
        "DP-3" = { mode = "5120x1440@239.761002Hz"; };
        #"DP-*" = { mode = "5120x1440@239.761002Hz"; };
        "Virtual-1" = { resolution = "1920x1200"; };
        "HDMI-A-3" = { mode = "800x480@65.681Hz"; };
      };
      startup = [
        { command = "systemctl --user import-environment SWAYSOCK"; always = false; }
        { command = "systemctl --user restart waybar"; always = true; }
        { command = ''
            swayidle \
              timeout 600 'swaymsg "output * dpms off"' \
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
      ++ lib.optionals (config.hostId == "yoga") [ ]
      ++ lib.optionals (config.hostId == "workvm") [ {
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
