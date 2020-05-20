{ config, pkgs, lib, ... }:

let
  miflora_config = pkgs.writeTextDir "config.ini" (builtins.readFile ./config.ini);
  miflora-mqtt-daemon = (pkgs.callPackage ../../../packages/miflora-mqtt-daemon { });
in {

  networking.hostName = "orangepi-prime";
  hardware.bluetooth.enable = true;

  hardware.deviceTree = {
    enable = true;
    overlays = [
      "${pkgs.dt-overlays}/sun50i-h5-uart1.dts.dtbo"
    ];
  };

  systemd.services.miflora = {
    description = "run miflora";
    requires = [ "wpa_supplicant.service" ];
    script = ''
      ${miflora-mqtt-daemon}/bin/miflora-mqtt-daemon --config_dir ${miflora_config}
    '';
    wantedBy = [ "multi-user.target" ];
  };

  services.consul.interface =
    let interface = "wlan0"; in {
      advertise = interface;
      bind = interface;
    };

  imports = [
    ../common.nix
    ../../../profiles/wireless.nix
  ];
}
