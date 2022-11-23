{ config, pkgs, ... }:

{

  sconfig.pipewire = true;

  # for yubikey
  services.pcscd.enable = true;

  # enable sway
  security.pam.services.swaylock = { };
  services.gnome.gnome-keyring.enable = true;

  environment.loginShellInit = ''
    [[ "$(tty)" == /dev/tty1 ]] && startsway
  '';

  services.ofono = {
    enable = true;
  };

  services.flatpak.enable = true;
  xdg.portal = {
    enable = true;
    # extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];
    # gtkUsePortal = true;
    wlr.enable = true;
  };

  environment.systemPackages = with pkgs; [
    # save settings
    dconf

    # ios tethering
    ifuse
    libimobiledevice

    # PA Systray
    pasystray
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

  # gtk = {
  #   enable = true;
  #   font.name = "sans";
  #   gtk2.extraConfig = "gtk-application-prefer-dark-theme = true";
  #   gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
  #   theme = {
  #     package = pkgs.ayu-theme-gtk;
  #     name = "Ayu-Dark";
  #   };
  # };

  # home.qt = {
  #   enable = true;
  #   platformTheme = "gnome";
  #   style = {
  #     name = "adwaita";
  #     package = pkgs.adwaita-qt;
  #   };
  # };

  services.upower = {
    enable = true;
  };

  hardware.bluetooth = {
    enable = true;
    settings = {
      General = {
        ControllerMode = "bredr";
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };

  services.blueman.enable = true;

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
    enableDefaultFonts = false;
    enableGhostscriptFonts = false;
    fontDir.enable = false;
    fontconfig = {
      enable = true;
      defaultFonts = {
        sansSerif = [ "IBM Plex Sans" ];
        serif = [ "IBM Plex Sans" ];
        monospace = [ "Hack Nerd Font" ];
        emoji = [ "Noto Color Emoji" ];
      };
      localConf = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
        <fontconfig>
            <alias binding="weak">
                <family>monospace</family>
                <prefer>
                    <family>emoji</family>
                </prefer>
            </alias>
            <alias binding="weak">
                <family>sans-serif</family>
                <prefer>
                    <family>emoji</family>
                </prefer>
            </alias>
            <alias binding="weak">
                <family>serif</family>
                <prefer>
                    <family>emoji</family>
                </prefer>
            </alias>
        </fontconfig>
      '';
    };
    fonts = with pkgs; [
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

  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [ libva ];
  };
}
