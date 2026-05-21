{
  config,
  pkgs,
  lib,
  ...
}: let
  addons = pkgs.firefox-addons;

  # Define accepted permissions per extension.
  # When an extension updates and requests new permissions, the build will
  # fail with an assertion listing the unaccepted permissions, so you can
  # review and approve them explicitly.
  extensionPermissions = {
    ublock-origin = [
      "alarms"
      "dns"
      "menus"
      "privacy"
      "storage"
      "tabs"
      "unlimitedStorage"
      "webNavigation"
      "webRequest"
      "webRequestBlocking"
      "<all_urls>"
      "http://*/*"
      "https://*/*"
      "file://*/*"
      "https://easylist.to/*"
      "https://*.fanboy.co.nz/*"
      "https://filterlists.com/*"
      "https://forums.lanik.us/*"
      "https://github.com/*"
      "https://*.github.io/*"
      "https://github.com/uBlockOrigin/*"
      "https://ublockorigin.github.io/*"
      "https://*.reddit.com/r/uBlockOrigin/*"
    ];
    privacy-badger = [
      "<all_urls>"
      "alarms"
      "privacy"
      "storage"
      "tabs"
      "webNavigation"
      "webRequest"
      "webRequestBlocking"
    ];
    # bitwarden = [
    #   "<all_urls>" "*://*/*" "alarms" "clipboardRead" "clipboardWrite"
    #   "contextMenus" "idle" "storage" "tabs" "unlimitedStorage"
    #   "webNavigation" "webRequest" "webRequestBlocking" "notifications" "file:///*"
    # ];
    clearurls = [
      "<all_urls>"
      "webRequest"
      "webRequestBlocking"
      "storage"
      "unlimitedStorage"
      "contextMenus"
      "webNavigation"
      "tabs"
      "downloads"
    ];
    decentraleyes = [
      "privacy"
      "webNavigation"
      "webRequestBlocking"
      "webRequest"
      "unlimitedStorage"
      "storage"
      "tabs"
    ];
    duckduckgo-privacy-essentials = [
      "contextMenus"
      "webRequest"
      "webRequestBlocking"
      "*://*/*"
      "webNavigation"
      "activeTab"
      "tabs"
      "storage"
      "<all_urls>"
      "alarms"
    ];
    # floccus = [
    #   "*://*/*" "alarms" "bookmarks" "storage" "unlimitedStorage"
    #   "tabs" "tabGroups" "identity"
    # ];
    ghostery = [
      "alarms"
      "cookies"
      "storage"
      "scripting"
      "tabs"
      "activeTab"
      "webNavigation"
      "webRequest"
      "webRequestBlocking"
      "unlimitedStorage"
      "http://*/*"
      "https://*/*"
      "ws://*/*"
      "wss://*/*"
      "*://www.youtube.com/*"
    ];
    languagetool = [
      "activeTab"
      "storage"
      "contextMenus"
      "scripting"
      "alarms"
      "http://*/*"
      "https://*/*"
      "file:///*"
      "*://docs.google.com/document/*"
      "*://docs.google.com/presentation/*"
      "*://languagetool.org/*"
      "https://languagetool.org/*/webextension/premium-announcement*"
      "https://languagetool.org/webextension/premium-announcement*"
      "http://localhost:8000/*/webextension/premium-announcement*"
      "http://localhost:8000/webextension/premium-announcement*"
    ];
    disconnect = [
      "tabs"
      "webNavigation"
      "webRequest"
      "webRequestBlocking"
      "http://*/*"
      "https://*/*"
    ];
    react-devtools = [
      "scripting"
      "storage"
      "tabs"
      "clipboardWrite"
      "devtools"
      "<all_urls>"
    ];
    consent-o-matic = [
      "activeTab"
      "tabs"
      "storage"
      "<all_urls>"
    ];
    multi-account-containers = [
      "<all_urls>"
      "activeTab"
      "cookies"
      "contextMenus"
      "contextualIdentities"
      "history"
      "idle"
      "management"
      "storage"
      "unlimitedStorage"
      "tabs"
      "webRequestBlocking"
      "webRequest"
    ];
    sponsorblock = [
      "storage"
      "scripting"
      "unlimitedStorage"
      "https://sponsor.ajay.app/*"
      "https://*.youtube.com/*"
      "https://www.youtube-nocookie.com/embed/*"
    ];
    darkreader = [
      "alarms"
      "contextMenus"
      "storage"
      "tabs"
      "theme"
      "<all_urls>"
    ];
    libredirect = [
      "webRequest"
      "webRequestBlocking"
      "storage"
      "clipboardWrite"
      "contextMenus"
      "<all_urls>"
    ];
    canvasblocker = [
      "<all_urls>"
      "storage"
      "tabs"
      "webRequest"
      "webRequestBlocking"
      "contextualIdentities"
      "cookies"
      "privacy"
    ];
  };

  # Addons that have extensive domain-specific permissions (e.g. privacy-badger
  # lists every google.<tld> domain). We allowlist known API permissions and
  # accept any URL-pattern permissions for these addons.
  addonHasExtensiveDomainPerms = name:
    builtins.elem name ["privacy-badger" "clearurls"];

  checkPermissions = name: addon: let
    accepted = extensionPermissions.${name} or [];
    requested = addon.meta.mozPermissions or [];
    isUrlPattern = p: (builtins.match ".*[:/].*" p) != null;
    unaccepted =
      if addonHasExtensiveDomainPerms name
      then lib.subtractLists accepted (builtins.filter (p: !(isUrlPattern p)) requested)
      else lib.subtractLists accepted requested;
  in {
    assertion = unaccepted == [];
    message = "Firefox extension '${name}' has unaccepted permissions: ${builtins.toJSON unaccepted}. Review and add them to extensionPermissions in home/firefox.nix";
  };

  enabledAddons = {
    inherit
      (addons)
      ublock-origin
      privacy-badger
      clearurls
      decentraleyes
      duckduckgo-privacy-essentials
      ghostery
      languagetool
      disconnect
      react-devtools
      consent-o-matic
      multi-account-containers
      sponsorblock
      darkreader
      libredirect
      canvasblocker
      ;
  };
in {
  assertions = lib.mapAttrsToList checkPermissions enabledAddons;
  programs.firefox = {
    enable = true;
    configPath = "${config.xdg.configHome}/mozilla/firefox";
    package = pkgs.wrapFirefox pkgs.firefox-bin-unwrapped {
      extraPolicies = {
        NewTabPage = false;
        DisableFormHistory = true;
        SearchSuggestEnabled = false;
        CaptivePortal = false;
        DisableFirefoxStudies = true;
        DisablePocket = true;
        DisableTelemetry = true;
        DisableFirefoxAccounts = false;
        NoDefaultBookmarks = true;
        OfferToSaveLogins = false;
        OfferToSaveLoginsDefault = false;
        PasswordManagerEnabled = false;
        FirefoxHome = {
          Search = true;
          Pocket = false;
          Snippets = false;
          TopSites = false;
          Highlights = false;
        };
        UserMessaging = {
          ExtensionRecommendations = false;
          SkipOnboarding = true;
        };
        Preferences = {
          "browser.contentblocking.category" = {
            Status = "locked";
            Value = "strict";
          };
          "browser.zoom.siteSpecific" = {
            Status = "locked";
            Value = false;
          };
          "extensions.formautofill.available" = {
            Status = "locked";
            Value = "off";
          };
          "media.setsinkid.enabled" = {
            Status = "locked";
            Value = true;
          };
          "network.IDN_show_punycode" = {
            Status = "locked";
            Value = true;
          };
          "ui.key.menuAccessKeyFocuses" = {
            Status = "locked";
            Value = false;
          };
        };
      };
    };

    profiles = {
      grw = {
        id = 0;
        name = "grw";
        extensions.packages = builtins.attrValues enabledAddons;
        search = {
          force = true;
          default = "ddg";
          engines = {
            "Nix Packages" = {
              urls = [
                {
                  template = "https://search.nixos.org/packages";
                  params = [
                    {
                      name = "type";
                      value = "packages";
                    }
                    {
                      name = "query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
              definedAliases = ["@np"];
            };
            "NixOS Wiki" = {
              urls = [{template = "https://nixos.wiki/index.php?search={searchTerms}";}];
              icon = "https://nixos.wiki/favicon.png";
              definedAliases = ["@nw"];
            };
            "wikipedia".metaData.alias = "@wiki";
            "google".metaData.hidden = true;
            "amazondotcom-us".metaData.hidden = true;
            "bing".metaData.hidden = true;
            "ebay".metaData.hidden = true;
          };
        };
        settings = {
          "general.smoothScroll" = true;
          "widget.wayland.use-primary-selection" = true;
        };
        extraConfig = ''
          user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
          user_pref("full-screen-api.ignore-widgets", true);
          user_pref("media.ffmpeg.vaapi.enabled", true);
          user_pref("media.rdd-vpx.enabled", true);
        '';
      };
    };
  };
}
