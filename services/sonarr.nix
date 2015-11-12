{ config, lib, pkgs, ... }:

{
  systemd.services.sonarr = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull linuxserver/sonarr''
        ''-${pkgs.docker}/bin/docker stop sonarr''
        ''-${pkgs.docker}/bin/docker rm sonarr''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --restart always \
        --name sonarr \
        --net="host" \
        -p 8989:8989 \
        -e PUID=1000 -e PGID=100 \
        -v /dev/rtc:/dev/rtc:ro \
        -v /storage/Media/TV:/tv \
        -v /storage/downloads/.sonarr:/downloads \
        -v /config/sonarr_config:/config \
        linuxserver/sonarr'';
      ExecStop = ''${pkgs.docker}/bin/docker stop sonarr'';
    };
  };
}
