{ config, lib, ... }:
let
  cfg = config.sconfig.pipewire;
in
{
  options.sconfig.pipewire = lib.mkEnableOption "Enable Pipewire";

  config = lib.mkIf cfg {
    hardware.pulseaudio.enable = false;
    services.pipewire = {
      enable = true;
      pulse.enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
    };
  };
}
