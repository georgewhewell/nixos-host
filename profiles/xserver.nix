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
    kitty
    cool-retro-term
    mpv
    mpg123
    chromium
    thunderbird
    shotwell
    ifuse
    libimobiledevice

    discord
    plex-media-player

    # PA Systray
    pasystray
    pavucontrol
    pamixer
  ];

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
    ];
  };

  hardware.bluetooth = {
    enable = true;
    extraConfig = "
      [General]
      Enable=Source,Sink,Media,Socket
    ";
  };

  hardware.opengl = {
    enable = true;
    s3tcSupport = true;
    driSupport = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [
      vaapiVdpau
      (vaapiIntel.override { enableHybridCodec = true; })
      libvdpau-va-gl
      intel-media-driver
    ];
  };

  hardware.pulseaudio = {
    enable = true;
    package = pkgs.pulseaudioFull;
    extraModules = [ pkgs.pulseaudio-modules-bt ];
    support32Bit = true;
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

  services.usbmuxd = {
    enable = true;
  };

  services.xserver = {
    enable = true;
    autoRepeatDelay = 200;
    autoRepeatInterval = 35;
    autorun = true;

    desktopManager.xterm.enable = false;

    xkbOptions = "caps:escape";

    displayManager = {
      slim = {
        enable = true;
        defaultUser = "grw";
        theme = pkgs.fetchurl {
          url = "https://github.com/edwtjo/nixos-black-theme/archive/v1.0.tar.gz";
          sha256 = "13bm7k3p6k7yq47nba08bn48cfv536k4ipnwwp1q1l2ydlp85r9d";
        };
      };
    };

  };
}
