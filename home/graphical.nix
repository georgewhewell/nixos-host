{ config, pkgs, lib, inputs, ... }:

{

  imports = [
    ./alacritty.nix
    ./cursor.nix
    ./sway.nix
    ./firefox.nix
    ./thunderbird.nix
    ./hyprland.nix
    ./vscode.nix
  ];

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

  home.packages = with pkgs; [
    wl-clipboard
    wdisplays
    wlr-randr
    xdg-utils
    kitty
    gimp

    vlc
    tdesktop
    element-desktop
    monero-gui
    calibre
    xournal
    yt-dlp
    # inputs.zed
  ] ++ lib.optionals (pkgs.system == "x86_64-linux") [
    spotify
    signal-desktop
    tor-browser-bundle-bin
    discord
    zoom-us
    slack
    cool-retro-term
    openshot-qt
  ];

  # gtk = {
  #   enable = true;
  #   theme = {
  #     package = pkgs.flat-remix-gtk;
  #     name = "Flat-Remix-GTK-Grey-Darkest";
  #   };

  #   iconTheme = {
  #     package = pkgs.gnome.adwaita-icon-theme;
  #     name = "Adwaita";
  #   };

  #   font = {
  #     name = "Sans";
  #     size = 11;
  #   };
  # };

}
