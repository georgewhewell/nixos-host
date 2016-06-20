# i3 desktop config
{ pkgs, ... }:

{
  environment.x11Packages = with pkgs; [
    dmenu     # for app launcher
    feh       # for background image
    i3lock    # screen lock
    i3status  # sys info
    scrot     # for screenshot
  ];

  hardware.opengl.driSupport32Bit = true;

  services.xserver = {
    enable = true;
    autorun = true;

    windowManager = {
      i3.enable = true;
      default = "i3";
    };

    displayManager = {
      slim.enable = true;
      sessionCommands = ''
        i3status &
      '';
    };
   };
}
