{ config, pkgs, lib, ... }:

{

  imports = [
    ./alacritty.nix
    ./sway.nix
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

  services.spotifyd = {
    enable = true;
    settings.global = {
      username = "georgerw@gmail.com";
      password = "STa3dKu1sucxGKhVbbZCk9IZ2";
      device_name = "fuckup";
      use_mpris = true;
      backend = "pulseaudio";
      device_type = "computer";
    };
  };

  home.packages = with pkgs; [
    wl-clipboard
    wdisplays

    spotify
    vlc

    signal-desktop
    tdesktop
    element-desktop
    tor-browser-bundle-bin
    monero-gui
    discord
    zoom-us
    # calibre
    slack
    xournal
    xdg-utils

    (wrapFirefox firefox-unwrapped {
      extraPolicies = {
        NewTabPage = false;
        CaptivePortal = false;
        DisablePocket = true;
        DisableFirefoxStudies = true;
        OfferToSaveLogins = false;
        DisableFormHistory = true;
        SearchSuggestEnabled = false;
        Preferences = {
          "browser.contentblocking.category" = { Status = "locked"; Value = "strict"; };
          "browser.zoom.siteSpecific" = { Status = "locked"; Value = false; };
          "extensions.formautofill.available" = { Status = "locked"; Value = "off"; };
          "media.setsinkid.enabled" = { Status = "locked"; Value = true; };
          "network.IDN_show_punycode" = { Status = "locked"; Value = true; };
          "ui.key.menuAccessKeyFocuses" = { Status = "locked"; Value = false; };
        };
      };
    })
  ];

}
