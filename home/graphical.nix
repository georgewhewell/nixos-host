{ config, pkgs, lib, ... }:

{

  imports = [
    ./alacritty.nix
    # ./sway.nix
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
    xdg-utils
    kitty

    vlc
    tdesktop
    element-desktop
    monero-gui
    calibre
    xournal
  ] ++ lib.optionals (pkgs.system == "x86_64-linux") [
    spotify
    signal-desktop
    tor-browser-bundle-bin
    discord
    zoom-us
    slack
  ] ++ [
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
