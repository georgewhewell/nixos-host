{ config, lib, pkgs, ... }:

{

  fileSystems."/var/lib/plex" =
    { device = "fpool/root/config/plex";
      fsType = "zfs";
    };

  networking.firewall.allowedTCPPorts = [ 32400 ];

  systemd.services.plex = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --rm \
        --net="host" \
        -e VERSION=latest \
        -e PUID=${toString config.ids.uids.transmission} \
        -e PGID=${toString config.gids.gids.transmission} \
        -e TZ=UTC \
        -v /var/lib/plex:/config \
        -v /mnt/Media/TV:/data/tvshows \
        -v /mnt/Media/Movies:/data/movies \
        -v /mnt/Media/transcode:/transcode \
        linuxserver/plex'';
    };
  };
}