{ config, lib, ... }:
let
  cfg = config.sconfig.pipewire;
in
{
  options.sconfig.pipewire = lib.mkEnableOption "Enable Pipewire";

  config = lib.mkIf cfg {
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      pulse.enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
    };
  };
}
