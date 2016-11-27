{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 5050 ];

  fileSystems."/var/lib/couchpotato" =
    { device = "fpool/root/config/couchpotato";
      fsType = "zfs";
    };

  systemd.services.couchpotato = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --rm \
        --net=host \
        -e TZ=Europe/London \
        -e PUID=${toString config.ids.uids.transmission} \
        -e PGID=${toString config.ids.gids.transmission} \
        -v /mnt/Media/Movies:/movies \
        -v /mnt/Media/downloads:/downloads \
        -v /var/lib/couchpotato:/config \
        linuxserver/couchpotato'';
    };
  };
}
