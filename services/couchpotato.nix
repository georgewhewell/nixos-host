{ config, lib, pkgs, ... }:

{
  systemd.services.couchpotato = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull needo/couchpotato''
        ''-${pkgs.docker}/bin/docker stop couchpotato''
        ''-${pkgs.docker}/bin/docker rm couchpotato''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --restart always \
        --name couchpotato \
        --net="host" \
        -e EDGE=1 \
        -p 5050:5050 \
        -v /etc/localtime:/etc/localtime:ro \
        -v /mnt/Media/Movies:/movies \
        -v /mnt/storage/downloads:/downloads \
        -v /config/couchpotato_config:/config \
        needo/couchpotato'';
      ExecStop = ''${pkgs.docker}/bin/docker stop couchpotato'';
    };
  };
}
