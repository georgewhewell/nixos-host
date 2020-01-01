{ config, lib, pkgs, ... }:


with lib;

let
  cfg = config.blind-engine;
in {

  options.blind-engine = {

    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable blind engine control
      '';
    };

    macAddresses = mkOption {
      type = types.listOf types.string;
      default = [];
    };

  };

  config = mkIf cfg.enable (let

    blind_control = pkgs.callPackage ../packages/blind-control { };

  in {

    systemd.services.align-blinds = {
      description = "align blinds with sun";
      script = ''
        ${blind_control}/bin/blind_control 02:be:75:37:b6:0a --astral
        ${blind_control}/bin/blind_control 02:c4:da:36:73:79 --astral
      '';
      startAt = "*:0/15";
    };

    systemd.services.open-blinds = {
      description = "open blinds";
      script = ''
        ${blind_control}/bin/blind_control 02:be:75:37:b6:0a
        ${blind_control}/bin/blind_control 02:c4:da:36:73:79
      '';
    };

    systemd.services.close-blinds = {
      description = "close blinds";
      script = ''
        ${blind_control}/bin/blind_control 02:be:75:37:b6:0a --close
        ${blind_control}/bin/blind_control 02:c4:da:36:73:79 --close
      '';
    };

  });

}
