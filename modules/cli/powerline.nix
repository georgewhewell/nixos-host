{ config, pkgs, lib, ... }:
let

  cfg = config.sconfig.powerline;

  theme = pkgs.writeText "powerline.json" (builtins.toJSON
    {
      CwdFg = 15;
      PathFg = 15;
      PathBg = 24;
      SeparatorFg = 16;
    });

in
{
  options.sconfig.powerline =
    {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "-modules=\${remote:+'user,host,'}nix-shell,shlvl,git,jobs,cwd"
          "-git-assume-unchanged-size 0"
          "-theme ${theme}"
          "-path-aliases '~/git=~/git'"
          "-jobs $(jobs -p | wc -l)"
        ] ++ config.sconfig.powerline.extraArgs;
      };
      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = [
      (pkgs.powerline-go.overrideAttrs (old: {
        patches = [
          # ./bold.patch
          ./shlvl.patch
        ];
      }))
    ];

    programs.bash.interactiveShellInit = ''
      function _update_ps1() {
        local remote=y
        [ "$XDG_SESSION_TYPE" = "x11" ] && unset remote
        [ "$XDG_SESSION_TYPE" = "wayland" ] && unset remote
        PS1="\n$(powerline-go ${lib.concatStringsSep " " cfg.args})"
      }
      [ "$TERM" = "linux" ] || PROMPT_COMMAND="_update_ps1; $PROMPT_COMMAND"
    '';

  };
}
