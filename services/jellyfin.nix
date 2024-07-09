{ config, pkgs, lib, ... }:

{

  services.jellyfin = {
    enable = true;
  };

  networking.firewall.allowedTCPPorts = [ 1900 9100 8096 ];
  networking.firewall.allowedUDPPorts = [ 1900 8096 ];

  environment.systemPackages = with pkgs; [ ffmpeg libva1 libva-utils ];

  fileSystems."/var/cache/jellyfin/transcodes" = {
    device = "none";
    fsType = "tmpfs";
    options = [ "defaults" "size=16G" "mode=755" "uid=992" "gid=990" ];
  };

}
