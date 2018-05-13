{ config, pkgs, ... }:

let
  oledBrightness = pkgs.writeScriptBin "oled-brightness" ''
    OLED_BR=`${pkgs.xorg.xrandr}/bin/xrandr --verbose | grep -i brightness | cut -f2 -d ' '`
    CURR=`LC_ALL=C printf "%.*f" 1 $OLED_BR`
    MIN=0
    MAX=1.2

    if [ "$1" == "up" ]; then
        VAL=`echo "scale=1; $CURR+0.1" | bc`
    else
        VAL=`echo "scale=1; $CURR-0.1" | bc`
    fi

    if (( `echo "$VAL < $MIN" | bc -l` )); then
        VAL=$MIN
    elif (( `echo "$VAL > $MAX" | bc -l` )); then
        VAL=$MAX
    else
        if [ "$1" == "up" ]; then
            for I in {1..10..1}; do ${pkgs.xorg.xrandr}/bin/xrandr --output eDP1 --brightness `echo "scale=2; $I/100+$CURR" | ${pkgs.bc}/bin/bc` 2>&1 >/dev/null | logger -t oled-brightness; done
        else
            for I in {1..10..1}; do ${pkgs.xorg.xrandr}/bin/xrandr --output eDP1 --brightness `echo "scale=2; $CURR-$I/100" | ${pkgs.bc}/bin/bc` 2>&1 >/dev/null | logger -t oled-brightness; done
        fi
    fi
  '';
  i3config = pkgs.writeText "i3-config" ''
    # Mod1 is Alt
    set $mod Mod1

    font pango:Hack 10

    # Use Mouse+$mod to drag floating windows to their wanted position
    floating_modifier $mod

    # start a terminal
    bindsym $mod+Return exec alacritty || urxvt

    # kill focused window
    bindsym $mod+Shift+q kill

    # start dmenu
    bindsym $mod+d exec ${pkgs.dmenu}/bin/dmenu_run

    # change focus
    bindsym $mod+j focus left
    bindsym $mod+k focus down
    bindsym $mod+l focus up
    bindsym $mod+semicolon focus right

    # move focused window
    bindsym $mod+Shift+j move left
    bindsym $mod+Shift+k move down
    bindsym $mod+Shift+l move up
    bindsym $mod+Shift+semicolon move right

    # splits
    bindsym $mod+h split h
    bindsym $mod+v split v

    # enter fullscreen mode for the focused container
    bindsym $mod+f fullscreen toggle

    # change container layout (stacked, tabbed, toggle split)
    bindsym $mod+s layout stacking
    bindsym $mod+w layout tabbed
    bindsym $mod+e layout toggle split
    bindsym $mod+Shift+space floating toggle

    # switch to workspace
    bindsym $mod+1 workspace 1
    bindsym $mod+2 workspace 2
    bindsym $mod+3 workspace 3
    bindsym $mod+4 workspace 4
    bindsym $mod+5 workspace 5
    bindsym $mod+6 workspace 6
    bindsym $mod+7 workspace 7
    bindsym $mod+8 workspace 8
    bindsym $mod+9 workspace 9
    bindsym $mod+0 workspace 10

    # move focused container to workspace
    bindsym $mod+Shift+1 move container to workspace 1
    bindsym $mod+Shift+2 move container to workspace 2
    bindsym $mod+Shift+3 move container to workspace 3
    bindsym $mod+Shift+4 move container to workspace 4
    bindsym $mod+Shift+5 move container to workspace 5
    bindsym $mod+Shift+6 move container to workspace 6
    bindsym $mod+Shift+7 move container to workspace 7
    bindsym $mod+Shift+8 move container to workspace 8
    bindsym $mod+Shift+9 move container to workspace 9
    bindsym $mod+Shift+0 move container to workspace 10

    # reload/restart
    bindsym $mod+Shift+c reload
    bindsym $mod+Shift+r restart

    # resize window (you can also use the mouse for that)
    bindsym $mod+r mode "resize"
    mode "resize" {
      # These bindings trigger as soon as you enter the resize mode

      # Pressing left will shrink the window’s width.
      # Pressing right will grow the window’s width.
      # Pressing up will shrink the window’s height.
      # Pressing down will grow the window’s height.
      bindsym j resize shrink width 10 px or 10 ppt
      bindsym k resize grow height 10 px or 10 ppt
      bindsym l resize shrink height 10 px or 10 ppt
      bindsym semicolon resize grow width 10 px or 10 ppt

      # same bindings, but for the arrow keys
      bindsym Left resize shrink width 10 px or 10 ppt
      bindsym Down resize grow height 10 px or 10 ppt
      bindsym Up resize shrink height 10 px or 10 ppt
      bindsym Right resize grow width 10 px or 10 ppt

      # back to normal: Enter or Escape
      bindsym Return mode "default"
      bindsym Escape mode "default"
    }

    # status bar
    bar {
      status_command ${pkgs.i3pystatus}/bin/i3pystatus -c ~/.config/i3/_i3pystatus.py
      colors {
        separator #268bd2
        background #002b36
        statusline #839496
        focused_workspace #fdf6e3 #6c71c4 #fdf6e3
        active_workspace #fdf6e3 #6c71c4 #fdf6e3
        inactive_workspace #002b36 #586e75 #002b36
        urgent_workspace #d33682 #d33682 #fdf6e3
      }
    }

    # Win+L locks the screen.
    bindsym Mod4+l exec xset s activate

    # No title/border
    for_window [class="^.*"] border pixel 0

    # EXIT
    bindsym $mod+Shift+e exec "i3-nagbar -t warning -m 'Exit?' -b 'Yes, exit i3' 'i3-msg exit'"

    # Media keystone
    bindsym XF86AudioMute exec "${pkgs.alsaUtils}/bin/amixer -q set Master toggle"
    bindsym XF86AudioLowerVolume exec "${pkgs.alsaUtils}/bin/amixer -q set Master 5-"
    bindsym XF86AudioRaiseVolume exec "${pkgs.alsaUtils}/bin/amixer -q set Master 5+"
    bindsym XF86AudioMicMute exec "${pkgs.alsaUtils}/bin/amixer -q set Capture toggle"

    bindsym XF86MonBrightnessDown exec "${oledBrightness}/bin/oled-brightness"
    bindsym XF86MonBrightnessUp exec "${oledBrightness}/bin/oled-brightness up"

    # lock screen
    # exec_always ${pkgs.xorg.xset}/bin/xset s 180 60

    # i3lock
    exec_always --no-startup-id ${pkgs.xss-lock}/bin/xss-lock -- ${pkgs.i3lock-fancy}/bin/i3lock-fancy -t "" -- ${pkgs.scrot}/bin/scrot

    # i3-gaps
    gaps inner 2
  '';
in {
  imports = [
    ../services/usbmuxd.nix
    ./gpg-yubikey.nix
  ];

  boot.kernelParams = [
    # https://gist.github.com/Brainiarc7/aa43570f512906e882ad6cdd835efe57
    "i915.enable_guc_loading=1"
    "i915.enable_guc_submission=1"
    "i915.enable_gvt=1"
    "i915.enable_fbc=1"
    "i915.enable_psr=1"
    "i915.disable_power_well=0"
  ];

  environment.systemPackages = with pkgs; [
    dmenu
    chromium
  ];

  fonts = {
    fontconfig = {
      useEmbeddedBitmaps = true;
      defaultFonts = {
        monospace = [ "Source Code Pro" ];
        sansSerif = [ "Source Sans Pro" ];
        serif     = [ "Source Serif Pro" ];
      };
    };
    fonts = with pkgs; [
      corefonts
      dejavu_fonts
      ubuntu_font_family
      hack-font
      powerline-fonts
      source-code-pro
      source-sans-pro
      source-serif-pro
    ];
  };

  hardware.bluetooth = {
    enable = true;
    extraConfig = "
      [General]
      Enable=Source,Sink,Media,Socket
    ";
  };

  systemd.services."dbus-org.bluez".serviceConfig.ExecStart =
    "${pkgs.bluez}/sbin/bluetoothd -n -d --compat";

  hardware.opengl = {
    enable = true;
    s3tcSupport = true;
    driSupport = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [
      vaapiVdpau
      vaapiIntel
      libvdpau-va-gl
    ];
  };

  hardware.pulseaudio = {
    enable = true;
    package = pkgs.pulseaudioFull;
    support32Bit = true;
    extraConfig = ''
      # stop switching to HDMI output
      unload-module module-switch-on-port-available
    '';
  };

  hardware.sane = {
    enable = true;
    snapshot = true;
  };

  services.printing = {
    enable = true;
    drivers = [ pkgs.gutenprint pkgs.hplip ];
  };

  services.xserver = {
    enable = true;
    autorun = true;



    desktopManager = {
      xterm.enable = false;
    };

    displayManager = {
      sessionCommands = ''
        ${pkgs.xlibs.xset}/bin/xset r rate 200 40
      '';
      slim = {
        defaultUser = "grw";
        theme = pkgs.fetchurl {
          url = "https://github.com/edwtjo/nixos-black-theme/archive/v1.0.tar.gz";
          sha256 = "13bm7k3p6k7yq47nba08bn48cfv536k4ipnwwp1q1l2ydlp85r9d";
        };
      };
    };

    windowManager = {
      default = "i3";
      i3 = {
        enable = true;
        configFile = i3config;
        package = pkgs.i3-gaps;
      };
    };
  };
}
