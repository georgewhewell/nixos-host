{ config, pkgs, ... }:

{
  imports = [
    ./gpg-yubikey.nix
  ];

  environment.systemPackages = with pkgs; [
    # save settings
    gnome3.dconf
    xorg.xbacklight
    libva-utils

    # Apps
    /* kitty */
    /* cool-retro-term */
    mpv
    mpg123
    /* chromium
    thunderbird */
    /* shotwell */
    ifuse
    libimobiledevice

#    discord
    /* plex-media-player */
    spotify

    # PA Systray
    pasystray
    pavucontrol
    pamixer
  ];

  hardware.bluetooth = {
    enable = true;
    extraConfig = "
      [General]
      Enable=Source,Sink,Media,Socket
    ";
  };

  users.users.pulse.extraGroups = [ "lp" ];
  hardware.pulseaudio = {
    enable = true;
    extraModules = [ pkgs.pulseaudio-modules-bt ];
    support32Bit = true;
    systemWide = true;
    extraConfig = ''
      # stop switching to HDMI output after resume
      unload-module module-switch-on-port-available

      # make bluetooth work?
      load-module module-bluetooth-policy
      load-module module-bluetooth-discover
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

  services.usbmuxd = {
    enable = true;
  };

  services.openssh.forwardX11 = true;

  fonts = {
    fontconfig = {
      useEmbeddedBitmaps = true;
      defaultFonts = {
        monospace = [ "Source Code Pro" ];
        sansSerif = [ "Source Sans Pro" ];
        serif     = [ "Source Serif Pro" ];
      };
    };
    fonts = with pkgs; [
      source-code-pro
      source-sans-pro
      source-serif-pro
    ];
  };

  services.redshift = {
    enable = true;
    brightness = {
      day = "1.0";
      night = "0.6";
    };
  };

  hardware.opengl = {
    enable = true;
    s3tcSupport = true;
    driSupport = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [ libva rocm-opencl-icd ];
  };

  services.xserver = {
    enable = true;
    autoRepeatDelay = 200;
    autoRepeatInterval = 35;
    autorun = true;

    desktopManager.xterm.enable = false;

    xkbOptions = "caps:escape";

    displayManager = {
       lightdm.enable = true;
    };

    windowManager.i3.enable = true;

  };
}
