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
        ''-${pkgs.docker}/bin/docker rm -f couchpotato''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --rm \
        --net="host" \
        -e EDGE=1 \
        -p 5050:5050 \
        -v /etc/localtime:/etc/localtime:ro \
        -v /mnt/Media/Movies:/movies \
        -v /mnt/storage/downloads:/mnt/storage/downloads \
        -v /mnt/oldnix/home/grw/couchpotato_config:/config \
        needo/couchpotato'';
      ExecStop = ''${pkgs.docker}/bin/docker rm -f couchpotato'';
    };
  };
}
