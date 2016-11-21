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
hardware.opengl.driSupport32Bit = true;

  services.xserver = {
    enable = true;
    autorun = true;

videoDrivers = ["intel"];
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
