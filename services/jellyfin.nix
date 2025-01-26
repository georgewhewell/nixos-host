{pkgs, ...}: {
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  systemd.services."jellyfin" = {
    bindsTo = ["mnt-Media.mount" "var-cache-jellyfin.mount"];
    after = ["mnt-Media.mount" "var-cache-jellyfin.mount"];
    serviceConfig.MemoryDenyWriteExecute = false;
  };

  users.users.jellyfin.extraGroups = ["video" "render"];

  environment.systemPackages = with pkgs; [ffmpeg libva1 libva-utils];

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
