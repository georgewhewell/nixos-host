{ config, pkgs, ... }:

{
  imports = [
    ../services/usbmuxd.nix
  ];

  hardware.pulseaudio = {
    enable = true;
    extraConfig = ''
      # stop switching to HDMI output
      unload-module module-switch-on-port-available
    '';
  };

  services.printing = {
    enable = true;
    drivers = [ pkgs.gutenprint ];
  };

  environment.systemPackages = with pkgs; [
    dmenu     # for app launcher
    feh       # for background image
    i3
    i3lock    # screen lock
    i3pystatus# sys info
    scrot     # for screenshot
    rxvt_unicode
    way-cooler
    alacritty
    xwayland
    sway
    polybar
  ];

  fonts.fontconfig = {
    defaultFonts = {
      monospace = [ "Hack" ];
      sansSerif = [ "Ubuntu" "Liberation Sans" "DejaVu Sans" ];
    };
    useEmbeddedBitmaps = true;
  };

  fonts.fonts = with pkgs; [
    corefonts
    dejavu_fonts
    ubuntu_font_family
    hack-font
    powerline-fonts
  ];

  hardware.opengl = {
    driSupport32Bit = true;
    s3tcSupport = true;
    extraPackages = with pkgs; [ vaapiIntel ];
  };

  services.xserver = {
    enable = true;
    autorun = true;

    desktopManager.xterm.enable = false;
    displayManager.slim.defaultUser = "grw";

    windowManager = {
      i3.enable = true;
      i3.package = pkgs.i3-gaps;
      default = "i3";
    };
  };
}
