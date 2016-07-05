# i3 desktop config
{ pkgs, ... }:

{
nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    dmenu     # for app launcher
    feh       # for background image
    i3
    i3lock    # screen lock
    i3status  # sys info
    scrot     # for screenshot
    rxvt_unicode
  ];

  fonts.fontconfig = {
    defaultFonts = {
      monospace = [ "Inconsolata" "Source Code Pro" "DejaVu Sans Mono" ];
      sansSerif = [ "Ubuntu" "Liberation Sans" "DejaVu Sans" ];
    };
    ultimate = {
      rendering = {
        INFINALITY_FT_FILTER_PARAMS = "08 24 36 24 08";
        INFINALITY_FT_FRINGE_FILTER_STRENGTH = "25";
        INFINALITY_FT_USE_VARIOUS_TWEAKS = "true";
        INFINALITY_FT_WINDOWS_STYLE_SHARPENING_STRENGTH = "25";
        INFINALITY_FT_STEM_ALIGNMENT_STRENGTH = "15";
        INFINALITY_FT_STEM_FITTING_STRENGTH = "15";
      };
    };
  };
  fonts.fonts = with pkgs; [
    corefonts
    source-han-sans-japanese
    source-han-sans-korean
    source-han-sans-simplified-chinese
    source-code-pro
    dejavu_fonts
    ubuntu_font_family
    inconsolata
    libertine
    unifont
  ];

  services.xserver = {
    enable = true;
    autorun = true;

    windowManager = {
      i3.enable = true;
      default = "i3";
    };

    displayManager = {
      sessionCommands = ''
        i3status &
      '';
    };
   };
}
