{
  config,
  lib,
  pkgs,
  ...
}: let
  # TTY launcher template — set XDG_CURRENT_DESKTOP + a few NVIDIA-friendly
  # env vars, push the env into systemd-user so D-Bus-activated services
  # (portals, pipewire, etc.) inherit it, then exec the compositor.
  #
  # stdout/stderr go to BOTH a timestamped log file under ~/.cache/start-logs
  # AND journald (via systemd-cat, tagged start-<name>). After a session
  # exits you can read the file directly or `journalctl --user -t start-<name>`.
  mkStart = {
    name,
    desktop,
    exec,
    extraEnv ? "",
  }:
    pkgs.writeShellScriptBin "start-${name}" ''
      #!${pkgs.bash}/bin/bash
      set -e

      export XDG_CURRENT_DESKTOP=${desktop}
      export XDG_SESSION_TYPE=wayland
      export XDG_SESSION_DESKTOP=${desktop}
      export GDK_BACKEND=wayland,x11
      export QT_QPA_PLATFORM="wayland;xcb"
      export MOZ_ENABLE_WAYLAND=1
      ${extraEnv}

      ${pkgs.systemd}/bin/systemctl --user import-environment \
        PATH XDG_DATA_DIRS XDG_CONFIG_DIRS \
        XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP \
        WAYLAND_DISPLAY DISPLAY 2>/dev/null || true

      LOG_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/start-logs"
      ${pkgs.coreutils}/bin/mkdir -p "$LOG_DIR"
      LOG_FILE="$LOG_DIR/${name}-$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S).log"
      ${pkgs.coreutils}/bin/ln -sf "$LOG_FILE" "$LOG_DIR/${name}-latest.log"

      # tee stderr+stdout to the log file AND to systemd-cat (journald, tagged).
      exec > >(${pkgs.coreutils}/bin/tee "$LOG_FILE" | ${pkgs.systemd}/bin/systemd-cat -t start-${name}) 2>&1
      exec ${exec}
    '';
in {
  # Niri: scrolling Wayland compositor (PaperWM-style).
  programs.niri.enable = true;

  # KDE Plasma 6 (Wayland session). Brings KWin + plasmashell + portals.
  services.desktopManager.plasma6.enable = true;

  # GNOME (Wayland session). Mutter + gnome-shell + portals.
  services.desktopManager.gnome.enable = true;

  environment.systemPackages = [
    # niri ships its own `niri` binary; wrap it to match the start-* pattern.
    (mkStart {
      name = "niri";
      desktop = "niri";
      exec = "${pkgs.niri}/bin/niri --session";
    })

    (mkStart {
      name = "plasma";
      desktop = "KDE";
      exec = "${pkgs.kdePackages.plasma-workspace}/bin/startplasma-wayland";
    })

    (mkStart {
      name = "gnome";
      desktop = "GNOME";
      # Use gnome-session with explicit "gnome" target.
      exec = "${pkgs.gnome-session}/bin/gnome-session --session=gnome";
    })
  ]
  # Apps the niri default config binds to (otherwise Mod+T / Mod+D do nothing).
  ++ (with pkgs; [fuzzel swaylock]);
}
