{ config, pkgs, lib, ... }:

{

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  systemd.services.jellyfin = {
    requires = [ "var-lib-jellyfin.mount" ];
    after = [ "var-lib-jellyfin.mount" ];
  };

  # users.users.jellyfin = {
  #   uid = 1099;
  #   group = "jellyfin";
  #   extraGroups = [ "audio" "video" ];
  # };

  # users.groups.jellyfin = {
  #   gid = 1099;
  # };

  networking.firewall.allowedTCPPorts = [ 1900 9100 8920 8096 ];
  networking.firewall.allowedUDPPorts = [ 1900 5355 ];

  environment.systemPackages = with pkgs; [ ffmpeg libva1 libva-utils ];

  fileSystems."/var/lib/jellyfin" = {
    device = "192.168.23.8:/jellyfin";
    fsType = "nfs4";
    options = [
      "nofail"
      "rw"
      # "noatime"
      # "nodiratime"
      "vers=4.2"
      # "tcp"
      "rsize=1048576"
      "wsize=1048576"
      # "timeo=600"
      # "retrans=2"
      # "noresvport"
      # "nconnect=8"
      # "uid=${toString config.users.users.jellyfin.uid}"
      # "gid=${toString config.users.groups.jellyfin.gid}"
    ];
  };


  fileSystems."/var/cache/jellyfin" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "nofail"
      "defaults"
      "size=16G"
      "mode=755"
      # "uid=${toString config.users.users.jellyfin.uid}"
      # "gid=${toString config.users.groups.jellyfin.gid}"
    ];
  };

}
