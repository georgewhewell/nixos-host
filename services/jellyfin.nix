{ config, pkgs, lib, ... }:

{

  services.jellyfin = {
    enable = true;
  };

  networking.firewall.allowedTCPPorts = [ 1900 8096 ];
  networking.firewall.allowedUDPPorts = [ 1900 8096 ];

  environment.systemPackages = with pkgs; [ ffmpeg libva1 libva-utils ];

}
