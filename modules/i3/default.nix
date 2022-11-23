{ config, pkgs, lib, ... }:
let
  cfg = config.sconfig.i3;
in
{
  options.sconfig.i3 = {
    enable = lib.mkEnableOption "Enable the i3 Window Manager";
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
    };
  };

  config = lib.mkIf cfg.enable {
    services.xserver.windowManager.i3 = {
      enable = true;
      extraSessionCommands = ''
        echo 'Xft.dpi: 96' | xrdb -merge
        echo 'Xcursor.size: 24' | xrdb -merge
        xsetroot -solid '#333333'
      '';
      configFile = pkgs.runCommand "i3config" { } ''
        (
          cat '${pkgs.i3}/etc/i3/config' |
          sed 's/Mod1/Mod4/' |
          sed 's/^exec i3-config-wizard/#&/' |
          sed 's/^font.*/font pango:DejaVuSans, FontAwesome5Free 12/' |
          sed 's,status_command i3status,status_command i3status-rs ${./i3srs.toml} \n tray_output primary,' |
          sed 's/i3-sensible-terminal/alacritty/' |
          sed 's/10%/2%/'
          cat '${pkgs.writeText "i3extra" cfg.extraConfig}'
        )|
        tee "$out"
      '';
    };

    hardware.pulseaudio.enable = true;

    environment.etc."xdg/gtk-3.0/settings.ini".text = ''
      [Settings]
      gtk-theme-name=Yaru-dark
      gtk-icon-theme-name=Numix
    '';

    sconfig.i3.extraConfig = ''
      default_border normal 4
      default_floating_border normal 4
      bindsym Mod4+Escape kill
      hide_edge_borders both
      bindsym XF86MonBrightnessUp   exec brightnessctl -n500 -e s -- +10%
      bindsym XF86MonBrightnessDown exec brightnessctl -n500 -e s -- -10%
    '';

    services.gvfs.enable = true;
    networking.networkmanager.enable = true;

    fonts.fonts = with pkgs; [
      font-awesome
      powerline-fonts
    ];

    services.xserver = {
      enable = true;
      libinput.enable = true;
      libinput.touchpad.naturalScrolling = true;
      displayManager.sddm.enable = true;
    };

    environment.systemPackages = with pkgs; [
      unstable.i3status-rust # 21.11 version supports zfs ARC
      brightnessctl
      numix-icon-theme
      yaru-theme
      gnome3.networkmanagerapplet
      gnome3.file-roller
      gnome3.adwaita-icon-theme
      mate.mate-terminal
      xfce.thunar
      xfce.thunar-archive-plugin
      caffeine-ng

      (runCommand "default_cursor" { } ''
        mkdir -p $out/share/icons/default
        ln -sf /run/current-system/sw/share/icons/Yaru/cursor.theme $out/share/icons/default/index.theme
      '')

      (runCommand "x-terminal-emulator" { } ''
        mkdir -p $out/bin
        ln -s ${alacritty}/bin/alacritty $out/bin/x-terminal-emulator
      '')
    ];
  };
}
