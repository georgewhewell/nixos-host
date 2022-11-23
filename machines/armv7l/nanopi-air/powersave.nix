{ config, pkgs, ... }:

{
  boot.kernelParams = [
    #    "maxcpus=1"  # this doesnt lower power, although it does disable cpu :S
  ];

  hardware.deviceTree.overlays = [
    { name = "powersave"; dtsFile = ./powersave.dts; }
  ];

  systemd.services.disable-cpus = {
    description = "disable cpu 1-3";
    script = ''
      echo 0 > /sys/devices/system/cpu/cpu3/online
      echo 0 > /sys/devices/system/cpu/cpu2/online
      echo 0 > /sys/devices/system/cpu/cpu1/online
    '';
    wantedBy = [ "multi-user.target" ];
  };

  powerManagement = {
    cpufreq = {
      max = 480000;
    };
  };

}
