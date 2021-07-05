{ config, pkgs, ... }:

{

  imports = [
    ../services/deconz.nix
    ../services/home-assistant/default.nix
  ];

  services.influxdb = {
    enable = true;
  };

}
