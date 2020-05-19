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

  environment.systemPackages = with pkgs; [
    gattool
    miflora-mqtt-daemon
    (python3.withPackages (ps: [ ps.miflora ps.btlewrap ]))
  ];

  systemd.services.miflora = {
    description = "run miflora";
    script = ''
      ${miflora-mqtt-daemon}/bin/miflora-mqtt-daemon --config_dir ${miflora_config} 
    '';
    wantedBy = [ "multi-user.target" ];
  };

  imports = [
    ../common.nix
    ../../../profiles/wireless.nix
  ];
}
