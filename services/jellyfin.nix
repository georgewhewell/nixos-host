{pkgs, ...}: {
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  systemd.services."jellyfin" = {
    bindsTo = ["mnt-Media.mount"];
    after = ["mnt-Media.mount"];
    serviceConfig.MemoryDenyWriteExecute = false;
  };

  users.users.jellyfin.extraGroups = ["video" "render"];

  environment.systemPackages = with pkgs; [ffmpeg libva1 libva-utils];
}
