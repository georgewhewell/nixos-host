{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedUDPPorts = [ 1194 ];

  systemd.services.openvpn = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker pull kylemanna/openvpn''
        ''-${pkgs.docker}/bin/docker stop openvpn''
        ''-${pkgs.docker}/bin/docker rm openvpn''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --restart always \
        --name openvpn \
        --net="host" \
        --cap-add=NET_ADMIN \
        --volumes-from ovpn-data \
        kylemanna/openvpn'';
      ExecStop = ''${pkgs.docker}/bin/docker stop openvpn'';
    };
  };
}
