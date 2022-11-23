{ config, lib, pkgs, ... }:

let
  cfg = config.sconfig.gaming;
in
{
  options.sconfig.gaming.enable = lib.mkEnableOption "Enable Gaming";

  config = lib.mkIf cfg.enable
    {
      programs.steam = {
        enable = true;
        remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
        dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
      };
      environment.systemPackages = [ pkgs.steam-run ];
    };
}
