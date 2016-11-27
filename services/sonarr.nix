{ config, lib, pkgs, ... }:

{

  fileSystems."/var/lib/sonarr" =
    { device = "fpool/root/config/sonarr";
      fsType = "zfs";
    };

  networking.firewall.allowedTCPPorts = [ 8989 ];

  systemd.services.sonarr = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --rm \
        --net="host" \
        -e PUID=${toString config.ids.uids.transmission} \
        -e PGID=${toString config.ids.uids.transmission} \
        -v /mnt/Media/TV:/tv \
        -v /mnt/Media/downloads:/downloads \
        -v /var/lib/sonarr:/config \
        linuxserver/sonarr'';
    };
  };
}
