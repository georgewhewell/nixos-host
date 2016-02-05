{ config, lib, pkgs, ... }:

{

  systemd.services.spaceheater = {
    description = "ethminer";
    requires = [ "docker.service" ];
    serviceConfig = {
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker rm ethminer''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
       --name=ethminer \
       --privileged=true \
       --device=/dev/nvidia0:/dev/nvidia0 \
       --device=/dev/nvidiactl:/dev/nvidiactl \
       --device=/dev/nvidia-uvm:/dev/nvidia-uvm \
       --volume /zpool/ethash:/root/.ethash \
       ethminer \
       cpp-ethereum/ethminer/ethminer -F http://eth-eu.dwarfpool.com/7fd1f5afc3d775cb900352179eaeec932dad47ad -G --cuda-extragpu-mem 0 --cuda-block-size 128 --cuda-grid-size 2048 --cuda-schedule auto'';
      ExecStop = ''${pkgs.docker}/bin/docker stop ethminer'';
    };
  };

}
