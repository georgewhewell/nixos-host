# i3 desktop config
{ pkgs, ... }:

{
nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    dmenu     # for app launcher
    feh       # for background image
    i3
    i3lock    # screen lock
    i3pystatus# sys info
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
    source-code-pro
    dejavu_fonts
    ubuntu_font_family
    inconsolata
    libertine
    unifont
    ttf_bitstream_vera
    hack-font
  ];

  hardware.opengl = {
    driSupport32Bit = true;
    s3tcSupport = true;
    extraPackages = with pkgs; [ vaapiIntel ];
  };

  services.xserver = {
    enable = true;
    autorun = true;
    useGlamor = true;

    xrandrHeads = [
      { output = "HDMI-2"; monitorConfig = ''
        Option "Rotate" "right"
        Option "Broadcast RGB" "Full"
        ''; }
      { output = "DP-2"; primary = true; monitorConfig = ''
        Option "Broadcast RGB" "Full"
    '';}
    ];

    videoDrivers = [ "modesetting" ];
    windowManager = {
      i3.enable = true;
      i3.package = pkgs.i3-gaps;
      default = "i3";
    };
   };
}
