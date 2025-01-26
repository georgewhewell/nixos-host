{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ./alacritty.nix
    ./cursor.ni
    ./desktop-apps.nix
    ./sway.nix
    ./firefox.nix
    ./thunderbird.nix
    ./hyprland.nix
    ./vscode.nix
    ./zed.nix
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
    cool-retro-term
    openshot-qt
  ];
}
