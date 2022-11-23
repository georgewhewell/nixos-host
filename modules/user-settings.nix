{ config, pkgs, lib, ... }:
let
  cfg = config.sconfig.user-settings;
in
{
  options.sconfig.user-settings = lib.mkOption {
    type = lib.types.nullOr lib.types.lines;
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "my-settings" cfg)
    ];
  };
}
