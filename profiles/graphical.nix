{ config, pkgs, ... }:

{

  # for yubikey
  services.pcscd.enable = true;

  # enable sway
  programs.sway.enable = true;
  programs.waybar.enable = true;

  systemd.user.services.waybar.unitConfig.wants = [ "sway.service" ];

  environment.systemPackages = with pkgs; [
    # save settings
    gnome3.dconf

    # ios tethering
    ifuse
    libimobiledevice

    # PA Systray
    pasystray
    pavucontrol
    pamixer

    torbrowser
    monero-gui

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
    '')
  ];

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
        ${pkgs.sway}/bin/sway --debug
      '';
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };

  environment.sessionVariables = {
    _JAVA_AWT_WM_NONREPARENTING = "1";
  };

  hardware.bluetooth = {
    enable = true;
    config = {
      General = {
        Enable = "Source,Sink,Media,Socket";
      };
    };
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

  hardware.opengl = {
    enable = true;
    s3tcSupport = true;
    driSupport = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [ libva ];
  };
}
