{ config, lib, pkgs, ... }:

let
  cfg = config.hostId;
in {
  options = {
    hostId = lib.mkOption {
      default = null;
      description = ''
        Host identifier
      '';
    };
  };
}
