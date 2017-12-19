{ config, pkgs, ... }:

{
  imports = [
    ../services/usbmuxd.nix
    ./gpg-yubikey.nix
  ];

  environment.systemPackages = with pkgs; [
    dmenu     # for app launcher
    feh       # for background image
    i3
    i3lock    # screen lock
    i3pystatus# sys info
    scrot     # for screenshot
    rxvt_unicode
    xss-lock

    usbmuxd
    atom
    chromium
  ];

  fonts = {
    fontconfig = {
      useEmbeddedBitmaps = true;
      defaultFonts = {
        monospace = [ "Hack" ];
        sansSerif = [ "Ubuntu" "Liberation Sans" "DejaVu Sans" ];
      };
    };
    fonts = with pkgs; [
      corefonts
      dejavu_fonts
      ubuntu_font_family
      hack-font
      powerline-fonts
    ];
  };

  hardware.bluetooth.enable = true;
  systemd.services."dbus-org.bluez".serviceConfig.ExecStart =
    "${pkgs.bluez}/sbin/bluetoothd -n -d --compat";

  hardware.opengl = {
    s3tcSupport = true;
    extraPackages = with pkgs; [ vaapiIntel ];
  };

  hardware.pulseaudio = {
    enable = true;
    extraConfig = ''
      # stop switching to HDMI output
      unload-module module-switch-on-port-available
    '';
  };

  hardware.sane = {
    enable = true;
    snapshot = true;
  };

  services.printing = {
    enable = true;
    drivers = [ pkgs.gutenprint pkgs.hplip ];
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
