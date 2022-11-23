{ config, lib, pkgs, ... }:

# alacritty.yml is needed in both <current-system>/sw/etc/ and /etc/, or
# it won't work correctly in some environments (at least plasma+wayland)
# That's why it's in systemPackages AND environment.etc.
# (November 2021)

let
  cfg = config.sconfig.alacritty;

  configText = builtins.toJSON
    {
      env.TERM = "xterm-256color";
      font.size = 12;
      colors = {
        primary.background = "0x1e1e1e";
        primary.foreground = "0xdddddd";
        # Tango Dark
        normal.black = "0x2e3436";
        normal.red = "0xcc0000";
        normal.green = "0x4e9a06";
        normal.yellow = "0xc4a000";
        normal.blue = "0x3465a4";
        normal.magenta = "0x75507b";
        normal.cyan = "0x06989a";
        normal.white = "0xd3d7cf";
        bright.black = "0x555753";
        bright.red = "0xef2929";
        bright.green = "0x8ae234";
        bright.yellow = "0xfce94f";
        bright.blue = "0x729fcf";
        bright.magenta = "0xad7fa8";
        bright.cyan = "0x34e2e2";
        bright.white = "0xeeeeec";
      };
      key_bindings = [
        { action = "ScrollHalfPageDown"; mods = "Shift"; key = "PageDown"; }
        { action = "ScrollHalfPageUp"; mods = "Shift"; key = "PageUp"; }
        { action = "SpawnNewInstance"; mods = "Control|Shift"; key = "N"; }
        { action = "SpawnNewInstance"; mods = "Control|Shift"; key = "T"; }
      ];
    };

in
{
  options.sconfig.alacritty.enable = lib.mkEnableOption "Enable Alacritty";

  config = lib.mkIf cfg.enable {

    environment.etc."xdg/alacritty.yml".text = configText;

    environment.systemPackages = [
      pkgs.alacritty
      (pkgs.writeTextFile {
        name = "alacritty.yml";
        destination = "/etc/xdg/alacritty.yml";
        text = configText;
      })
    ];

    programs.bash.interactiveShellInit = ''
      function _set_title() {
        printf "\033]0;%s@%s:%s\007" "''${USER}" "''${HOSTNAME%%.*}" "''${PWD/#$HOME/\~}"
      }
      [ -z "$VTE_VERSION" ] && PROMPT_COMMAND="_set_title; $PROMPT_COMMAND"
    '';
  };
}
