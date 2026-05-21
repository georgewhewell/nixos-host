{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ./alacritty.nix
    ./kitty.nix
    # ./cursor.nix
    ./desktop-apps.nix
    ./waybar.nix
    ./sway.nix
    ./firefox.nix
    # ./thunderbird.nix
    ./hyprland.nix
    ./vscode.nix
    ./zed.nix
  ];

  # Set dark mode preference for GTK/portal apps (including Firefox "system" theme)
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    gtk4.theme = null;
  };

  xdg.mimeApps.defaultApplications = {
    "application/x-extension-htm" = "firefox.desktop";
    "application/x-extension-html" = "firefox.desktop";
    "application/x-extension-shtml" = "firefox.desktop";
    "application/x-extension-xht" = "firefox.desktop";
    "application/x-extension-xhtml" = "firefox.desktop";
    "application/xhtml+xml" = "firefox.desktop";
    "text/html" = "firefox.desktop";
    "x-scheme-handler/chrome" = "firefox.desktop";
    "x-scheme-handler/http" = "firefox.desktop";
    "x-scheme-handler/https" = "firefox.desktop";
  };

  services.spotifyd = {
    enable = true;
    settings.global = {
      device_name = config.hostId;
      device_type = "computer";
      backend = "pulseaudio";
      zeroconf_port = 1234;
    };
  };

  home.packages = with pkgs; [
    wl-clipboard
    wdisplays
    wlr-randr
    wf-recorder
    slurp
    xdg-utils
    gimp
    cool-retro-term
    # openshot-qt

    # Smartcard/Yubikey support
    ccid
    yubikey-manager
    opensc
    pcsc-tools
    bridge-utils

    # Terminal emulator terminfo
    ghostty.terminfo
  ];
}
