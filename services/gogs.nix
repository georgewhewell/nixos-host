{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 10080 2222];

  systemd.services.gogs = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull gogs/gogs''
        ''-${pkgs.docker}/bin/docker stop gogs''
        ''-${pkgs.docker}/bin/docker rm gogs''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --name gogs \
        -p 3000:3000 \
        -p 2222:22 \
        -v /mnt/gogs:/data \
        gogs/gogs'';
      ExecStop = ''${pkgs.docker}/bin/docker stop gogs'';
    };
  };
  
}
