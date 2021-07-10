{ config, pkgs, ... }:

{

  imports = [
    ./alacritty.nix
    ./sway.nix
  ];

  programs.firefox = {
    enable = true;
    /*
    package = pkgs.wrapFirefox pkgs.firefox-unwrapped {
      forceWayland = true;
      extraPolicies = {
	ExtensionSettings = {};
      };
      };
      */
  };

  home.packages = with pkgs; [
    wl-clipboard

    corefonts
    dejavu_fonts
    ubuntu_font_family
    hack-font
    roboto
    powerline-fonts
    font-awesome-ttf
    source-code-pro
    source-sans-pro
    source-serif-pro
    font-awesome_5

    steam
    spotify
    vlc
    zoom-us
    slack
    freeorion
  ];

  fonts.fontconfig.enable = pkgs.lib.mkForce true;

  services.redshift = {
    enable = true;
    package = pkgs.redshift-wlr;
    latitude = "51.5";
    longitude = "0";
    brightness = {
      day = "1";
      night = "0.6";
    };
  };
}
