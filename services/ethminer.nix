{ config, lib, pkgs, ... }:

{
  /*
    My room is cold in the morning, so spin the cpu/gpu for heat
    Since its 2016, waste computation is reclaimed in ethereum
  */

  systemd.services.spaceheater_start = {
    startAt = "03:00";
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
      /run/current-system/sw/bin/systemctl start ethminer_gpu
      '';
      ExecStop = ''
      /run/current-system/sw/bin/echo Started
      '';
    };
  };

  systemd.services.spaceheater_stop = {
    startAt = "08:30";
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
      /run/current-system/sw/bin/systemctl stop ethminer_gpu
      '';
      ExecStop = ''
      /run/current-system/sw/bin/echo Stopped
      '';
    };
  };

  /* 275W TDP */
  systemd.services.ethminer_gpu = {
    description = "ethminer gpu";
    requires = [ "docker.service" ];
    serviceConfig = {
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker rm ethminer''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
       --name=ethminer \
       --privileged=true \
       --device=/dev/nvidia0 \
       --device=/dev/nvidiactl \
       --device=/dev/nvidia-uvm \
       --volume /zpool/ethash:/root/.ethash \
       ethminer \
       cpp-ethereum/ethminer/ethminer -F http://eth-eu.dwarfpool.com/7fd1f5afc3d775cb900352179eaeec932dad47ad -U --cuda-extragpu-mem 0 --cuda-block-size 128 --cuda-grid-size 2048 --cuda-schedule auto'';
      ExecStop = ''${pkgs.docker}/bin/docker stop ethminer'';
    };
  };

  /* 95W TDP */
  systemd.services.ethminer_cpu = {
    description = "ethminer cpu";
    requires = [ "docker.service" ];
    serviceConfig = {
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker rm ethminer_cpu''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
       --name=ethminer_cpu \
       --volume /zpool/ethash:/root/.ethash \
       ethminer \
       cpp-ethereum/ethminer/ethminer -F http://eth-eu.dwarfpool.com/7fd1f5afc3d775cb900352179eaeec932dad47ad -C'';
      ExecStop = ''${pkgs.docker}/bin/docker stop ethminer_cpu'';
    };
  };
}
