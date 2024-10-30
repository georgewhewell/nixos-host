{ config, pkgs, lib, ... }:

{

  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  systemd.services."jellyfin" = {
    bindsTo = [ "mnt-Media.mount" "var-cache-jellyfin.mount" ];
    after = [ "mnt-Media.mount" "var-cache-jellyfin.mount" ];
  };

  users.users.jellyfin.extraGroups = [ "video" "render" ];

  environment.systemPackages = with pkgs; [ ffmpeg libva1 libva-utils ];

  fileSystems."/var/cache/jellyfin" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "nofail"
      "defaults"
      "size=16G"
      "mode=755"
    ];
  };

}
