{ config, lib, pkgs, boot, networking, containers, ... }:

{
  systemd.services."container@jellyfin" = {
    bindsTo = [ "mnt-Home.mount" "mnt-Media.mount" ];
    after = [ "mnt-Home.mount" "mnt-Media.mount" ];
  };

  imports = [
    ../profiles/nas-mounts.nix
  ];


  # services.nginx = {
  #   virtualHosts."radarr.satanic.link" = {
  #     forceSSL = true;
  #     enableACME = true;
  #     locations."/" = {
  #       extraConfig = ''
  #         resolver 192.168.23.5;
  #         proxy_buffering off;
  #       '';
  #       proxyPass = "http://radarr.lan:7878";
  #       proxyWebsockets = true;
  #     };
  #   };
  # };

  containers.jellyfin = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0.lan";

    bindMounts = {
      "/var/lib/jellyfin" = {
        hostPath = "/mnt/Media/jellyfin";
        isReadOnly = false;
      };
      "/mnt/Media" = {
        hostPath = "/mnt/Media";
        isReadOnly = false;
      };
      "/dev/dri" = {
        hostPath = "/dev/dri";
        isReadOnly = false;
      };
      "/dev/shm" = {
        hostPath = "/dev/shm";
        isReadOnly = false;
      };
    };

    config = {
      imports = [
        ../profiles/container.nix
        ../profiles/intel-gfx.nix
        ../services/jellyfin.nix
      ];

      users.users.jellyfin.extraGroups = [ "video" "render" ];

      networking.hostName = "jellyfin";
    };

  };
}
