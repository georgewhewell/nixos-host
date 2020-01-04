{ pkgs, ... }:

{

  imports = [
    ./alacritty.nix
    ./waybar.nix
  ];

  programs.firefox = {
    enable = true;
    package = pkgs.firefox-wayland;
  };

  xdg.configFile."sway/config".text = (import ./sway.nix { inherit pkgs; });

  home.packages = with pkgs; [
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

    spotify
    qutebrowser
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
