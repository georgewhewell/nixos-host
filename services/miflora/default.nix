{ config, lib, pkgs, ... }:

let
  miflora_config = pkgs.writeTextDir "config.ini" (builtins.readFile ./config.ini);
  miflora-mqtt-daemon = (pkgs.callPackage ../../packages/miflora-mqtt-daemon { });
in {

  systemd.services.miflora = {
    description = "run miflora";
    requires = [ "wpa_supplicant.service" ];
    script = ''
      ${miflora-mqtt-daemon}/bin/miflora-mqtt-daemon --config_dir ${miflora_config}
    '';
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5";
      StartLimitIntervalSec = "0";
      StartLimitBurst = "0";
    };
  };

}
