{ pkgs, ... }:

{
  services.polybar = {
    enable = true;
    package = pkgs.polybar.override {
      i3Support = true;
      alsaSupport = true;
      pulseSupport = true;
      githubSupport = true;
      iwSupport = true;
      nlSupport = false;
    };
    script = ''
      polybar bottom &
    '';
    config = rec {
      colors = {
        bgblue = "#010024";
        white = "#f8f8f8";
        pink = "#F92672";
        dpink = "#a01849";
        cyan = "#23ceef";
        dcyan = "#157b8f";
        purple = "#8e4fff";
        dpurple = "#5a32a2";
        orange = "#f4a63a";
        dorange = "#aa7428";
        green = "#A6E22E";
        dgreen = "#77A915";
        black = "#000000";
      };
      "paddings" = {
        inner = 1;
        outer = 4;
      };
      "bar/bottom" = {
        width = "100%";
        height = "32";
        dpi = 180;
        radius = 0;
        bottom = true;

        font-0 = "SourceSansPro:weight=regular:pixelsize=9;5";
        font-1 = "Font Awesome:style=Regular:antialias=true:size=9;5";

        font-2 = "Font Awesome 5 Free:style=Regular:pixelsize=9;5";
        font-3 = "Font Awesome 5 Free:style=Solid:pixelsize=9;5";
        font-4 = "Font Awesome 5 Brands:style=Regular:pixelsize=9;5";

        module-margin = 2;

        # Just sticking them together in the center for now
        modules-left = "i3";
        modules-center = "date";
        modules-right = "temperature cpu memory pulseaudio network battery";
      };
      "module/battery" = {
        type = "internal/battery";
        full-at = "98";

        format-charging-prefix = " ";
        format-charging = "<ramp-capacity> <label-charging>";
        label-charging = "%consumption%W %percentage%%";

        format-discharging = "<ramp-capacity> <label-discharging>";
        label-discharging = "%consumption%W %percentage%%";

        format-full = "%{F#666}%{F#ccfafafa}  <label-full>";

        ramp-capacity-0 = "";
        ramp-capacity-1 = "";
        ramp-capacity-2 = "";
        ramp-capacity-3 = "";
        ramp-capacity-4 = "";
      };
      "module/date" = {
        type = "internal/date";
        internal = 5;
        date = "%Y-%m-%d";
        time = "%H:%M";
        label = "%date% %time%";
      };
      "module/network" = {
        type = "internal/network";
        interface = "wlp3s0";
        #format-connected = "<label-connected>";
        format-connected-prefix = " ";
        #label-connected = "%essid% %{F#66}%local_ip% ";
        #label-disconnected = "%{F#666}%{F#ccfafafa} not connected";
        #label-disconnected-foreground = "#66";

        interval = "1.0";
        ping-interval = "10";

        format-connected = "<ramp-signal> <label-connected>";
        label-connected = "%essid% %local_ip%    %downspeed%    %upspeed%";
        label-disconnected = "   not connected";
        label-disconnected-foreground = "#66";

        ramp-signal-0 = "";
        ramp-signal-1 = "";
        ramp-signal-2 = "";
        ramp-signal-3 = "";
        ramp-signal-4 = "";

        animation-packetloss-0 = "";
        animation-packetloss-0-foreground = "#ffa64c";
        animation-packetloss-1 = "";
        animation-packetloss-framerate = 500;
      };
      "module/i3" = {
        type = "internal/i3";
        scroll-up = "i3wm-wsnext";
        scroll-down = "i3wm-wsprev";

        index-sort = "true";
        wrapping-scroll = "false";
        pin-workspaces = "true";
        strip-wsnumbers = "false";

        format = "<label-state> <label-mode>";

        label-font = 0;
        label-mode = "%mode%";
        label-mode-padding = 1;
        label-mode-background = "#e60053";

        label-focused = "%index%";
        label-focused-foreground = "#ffffff";
        label-focused-background = "#3f3f3f";
        label-focused-underline = "#fba922";
        label-focused-padding = 1;

        label-unfocused = "%index%";
        label-unfocused-padding = 1;

        label-visible = "%index%";
        label-visible-underline = "#555555";
        label-visible-padding = 1;

        label-urgent = "%index%";
        label-urgent-foreground = "#000000";
        label-urgent-background = "#bd2c40";
        label-urgent-padding = 1;

        label-separator = "|";
        label-separator-padding = 1;
        label-separator-foreground = "#ffb52a";

        ws-icon-0 = "1;";
        ws-icon-1 = "2;²";
        ws-icon-2 = "3;";
        ws-icon-3 = "4;²";
        ws-icon-4 = "5;";
        ws-icon-5 = "6;";
        ws-icon-6 = "6;6";
        ws-icon-7 = "7;7";
        ws-icon-8 = "8;8";
        ws-icon-9 = "9;";
        ws-icon-10 = "10;";
      };
      "module/pulseaudio" = {
        type = "internal/pulseaudio";
        format-volume = "<ramp-volume> <label-volume>";
        format-volume-prefix = "";
        format-muted = "<label-muted>";
        format-muted-prefix = " ";

        label-muted = "🔇 muted";
        label-muted-foreground = "#666";

        ramp-volume-0 = "🔈";
        ramp-volume-1 = "🔉";
        ramp-volume-2 = "🔊";
      };
      "module/cpu" = {
        type = "internal/cpu";
        interval = "0.5";
        format = "<ramp-load>";
      };
      "module/memory" = {
        type = "internal/memory";
        format = "<label> <ramp-used>";

        format-prefix = " ";

        ramp-used-0 = "▁";
        ramp-used-1 = "▂";
        ramp-used-2 = "▃";
        ramp-used-3 = "▄";
        ramp-used-4 = "▅";
        ramp-used-5 = "▆";
        ramp-used-6 = "▇";
        ramp-used-7 = "█";
      };
      "module/temperature" = {
        type = "internal/temperature";
        interval = "0.5";
        thermal-zone = "1";
        warn-temperature = "80";
      };
    };
  };
}
