{ config, lib, pkgs, ... }:

with pkgs.stdenv;
with lib;
let
  cfg = config.hardware.devicetree;
in
{

  options.hardware.devicetree = {

    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable devicetree-related functionality
      '';
    };

    dtbName = mkOption {
      type = types.str;
      example = "sun8i-h2-plus-orangepi-zero";
    };

    overlays = mkOption {
      type = types.listOf types.lines;
      default = ''
      '';
      description = ''
        DTB Overlay
      '';
    };
  };

  config = mkIf cfg.enable rec {
    system.build.dtbName = cfg.dtbName;
  };
  meta = { };
}
