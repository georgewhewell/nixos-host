{ pkgs, ... }:

{

  imports = [
    ./alacritty.nix
    ./waybar.nix
  ];

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

}
