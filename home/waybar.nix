{ config, pkgs, lib, ... }:

let
  # Re-import the running compositor's env into the user systemd manager
  # and dbus activation environment. Useful after session disruption (e.g.
  # OOM kills dbus-broker-launch) clears the imported vars and leaves
  # `systemctl --user restart waybar` failing on ConditionEnvironment.
  importGraphicalEnv = pkgs.writeShellScript "import-graphical-env" ''
    set -eu
    # Find the live wayland socket. Bail if no compositor is running.
    socket=$(${pkgs.findutils}/bin/find "/run/user/$UID" -maxdepth 1 \
      -name 'wayland-*' ! -name '*.lock' -printf '%f\n' 2>/dev/null | head -n1)
    if [ -z "$socket" ]; then
      echo "no wayland socket found in /run/user/$UID" >&2
      exit 0
    fi
    export WAYLAND_DISPLAY="$socket"
    export XDG_SESSION_TYPE=wayland
    if [ -d "/run/user/$UID/hypr" ]; then
      his=$(${pkgs.coreutils}/bin/ls -t "/run/user/$UID/hypr" 2>/dev/null | head -n1 || true)
      if [ -n "$his" ]; then
        export HYPRLAND_INSTANCE_SIGNATURE="$his"
        export XDG_CURRENT_DESKTOP=Hyprland
      fi
    fi
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      WAYLAND_DISPLAY XDG_SESSION_TYPE \
      ''${HYPRLAND_INSTANCE_SIGNATURE:+HYPRLAND_INSTANCE_SIGNATURE} \
      ''${XDG_CURRENT_DESKTOP:+XDG_CURRENT_DESKTOP}
  '';
in
{
  systemd.user.services.import-graphical-env = {
    Unit = {
      Description = "Re-import wayland/Hyprland env into the user manager";
      # Run after the dbus broker so dbus-update-activation-environment
      # has somewhere to publish to. No PartOf — we want this to survive
      # graphical-session.target restarts.
      After = [ "dbus.service" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = false;
      ExecStart = toString importGraphicalEnv;
    };
  };

  programs.waybar = {
    enable = true;
    systemd.enable = true;
    style = ''
      ${builtins.readFile "${pkgs.waybar}/etc/xdg/waybar/style.css"}

      window#waybar {
        background: transparent;
        border-bottom: none;
      }

      #workspaces button.active {
        background-color: #64727D;
        box-shadow: inset 0 -3px #ffffff;
      }

      * {
        ${if config.hostId == "yoga" then ''
        font-size: 18px;
      '' else ''

        ''}
      }
    '';
    settings = [{
      height = 30;
      layer = "top";
      position = "bottom";
      tray = { spacing = 10; };
      modules-center = [ "sway/window" "hyprland/window" ];
      modules-left = [ "sway/workspaces" "hyprland/workspaces" "sway/mode" "hyprland/submap" ];
      modules-right = [
        "pulseaudio"
        "network"
        "cpu"
        "memory"
        "temperature"
      ] ++ (if config.hostId == "yoga" then [ "battery" ] else [ ])
      ++ [
        "clock"
        "tray"
      ];
      battery = {
        format = "{capacity}% {icon}";
        format-alt = "{time} {icon}";
        format-charging = "{capacity}% ";
        format-icons = [ "" "" "" "" "" ];
        format-plugged = "{capacity}% ";
        states = {
          critical = 15;
          warning = 30;
        };
      };
      clock = {
        format-alt = "{:%Y-%m-%d}";
        tooltip-format = "{:%Y-%m-%d | %H:%M}";
      };
      cpu = {
        format = "{usage}% ";
        tooltip = false;
      };
      memory = { format = "{}% "; };
      network = {
        interval = 1;
        format-alt = "{ifname}: {ipaddr}/{cidr}";
        format-disconnected = "Disconnected ⚠";
        format-ethernet = "{ifname}: {ipaddr}/{cidr}   up: {bandwidthUpBits} down: {bandwidthDownBits}";
        format-linked = "{ifname} (No IP) ";
        format-wifi = "{essid} ({signalStrength}%) ";
      };
      pulseaudio = {
        format = "{volume}% {icon} {format_source}";
        format-bluetooth = "{volume}% {icon} {format_source}";
        format-bluetooth-muted = " {icon} {format_source}";
        format-icons = {
          car = "";
          default = [ "" "" "" ];
          handsfree = "";
          headphones = "";
          headset = "";
          phone = "";
          portable = "";
        };
        format-muted = " {format_source}";
        format-source = "{volume}% ";
        format-source-muted = "";
        on-click = "pavucontrol";
      };
      "sway/mode" = { format = ''<span style="italic">{}</span>''; };
      "hyprland/workspaces" = {
        on-scroll-up = "hyprctl dispatch workspace e+1";
        on-scroll-down = "hyprctl dispatch workspace e-1";
      };
      "hyprland/submap" = { format = ''<span style="italic">{}</span>''; };
      temperature = {
        critical-threshold = 80;
        format = "{temperatureC}°C {icon}";
        format-icons = [ "" "" "" ];
      };
    }];
  };
}
