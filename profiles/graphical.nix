{ config, pkgs, ... }:

{

  sconfig.pipewire = true;
  # hardware.pulseaudio.enable = true;

  # for yubikey
  services.pcscd.enable = true;

  # enable sway
  # security.pam.services.swaylock = { };
  services.gnome.gnome-keyring.enable = true;

  /*
    environment.loginShellInit = ''
    [[ "$(tty)" == /dev/tty1 ]] && startsway
    '';
  */

  # services.ofono = {
  #   enable = true;
  # };

  # services.flatpak.enable = true;
  # xdg.portal = {
  #   enable = true;
  #   # extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];
  #   # gtkUsePortal = true;
  #   wlr.enable = true;
  # };
  # services.xserver.enable = false;

  # NOTE: Just to try wlroots + displaylink
  environment.etc."modprobe.d/evdi.conf".text = ''
    softdep evdi pre: i915 drm_display_helper
    options evdi initial_device_count=2 initial_loglevel=3
  '';

  services.xserver.videoDrivers = [ "displaylink" "modesetting" ];
  boot.extraModulePackages = [
    config.boot.kernelPackages.evdi
  ];

  xdg.portal.config.common.default = "*";
  environment.systemPackages = with pkgs; [
    # save settings
    dconf

    # ios tethering
    ifuse
    libimobiledevice

    # PA Systray
    # pasystray
    pavucontrol
    pamixer

    (pkgs.writeScriptBin "startsway" ''
      #! ${pkgs.bash}/bin/bash

      # kill weird less vars
      unset LESS_TERMCAP_so
      unset LESS_TERMCAP_se
      unset LESS_TERMCAP_mb
      unset LESS_TERMCAP_md
      unset LESS_TERMCAP_me
      unset LESS_TERMCAP_ue
      unset LESS_TERMCAP_us

      # first import environment variables from the login manager
      systemctl --user import-environment

      # then start the service
      exec systemctl --user start sway.service
    ''
    )
  ];

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  systemd.user.targets.sway-session = {
    description = "Sway compositor session";
    documentation = [ "man:systemd.special(7)" ];
    bindsTo = [ "graphical-session.target" ];
    wants = [ "graphical-session-pre.target" ];
    after = [ "graphical-session-pre.target" ];
  };

  systemd.user.services.sway = {
    description = "Sway - Wayland window manager";
    documentation = [ "man:sway(5)" ];
    bindsTo = [ "graphical-session.target" ];
    wants = [ "graphical-session-pre.target" ];
    after = [ "graphical-session-pre.target" ];
    # We explicitly unset PATH here, as we want it to be set by
    # systemctl --user import-environment in startsway
    environment.PATH = pkgs.lib.mkForce null;
    serviceConfig = {
      Type = "simple";
      ExecStart = ''
        ${pkgs.sway}/bin/sway
      '';
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };

  # services.upower = {
  #   enable = true;
  # };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        ControllerMode = "bredr";
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };

  services.blueman.enable = true;

  zramSwap.enable = true;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      userServices = true;
    };
  };

  services.usbmuxd = {
    enable = true;
  };

  services.openssh.settings.X11Forwarding = true;

  fonts = {
    enableDefaultPackages = true;
    enableGhostscriptFonts = true;
    # fontDir.enable = false;
    fontconfig = {
      enable = true;
      defaultFonts = {
        sansSerif = [ "IBM Plex Sans" ];
        serif = [ "IBM Plex Sans" ];
        monospace = [ "Hack Nerd Font" ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
    packages = with pkgs; [
      (nerdfonts.override { fonts = [ "Hack" ]; })
      ibm-plex
      dejavu_fonts
      unifont
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-emoji
      noto-fonts-extra
    ];
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ libva ];
  };
}
