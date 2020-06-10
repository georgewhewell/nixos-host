{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 5060 ];

  fileSystems."/var/lib/cardigann" =
    {
      device = "fpool/root/config/cardigann";
      fsType = "zfs";
    };

  systemd.services.cardigann = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --rm \
        --net=host \
        -e CONFIG_DIR=/var/lib/cardigann \
        -v /var/lib/cardigann:/var/lib/cardigann \
        cardigann/cardigann'';
    };
  };
}
