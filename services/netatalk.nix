{ config, lib, pkgs, ... }:

{
  fileSystems."/mnt/timemachine" =
    { device = "bpool/root/timemachine";
      fsType = "zfs";
    };

  networking.firewall.allowedTCPPorts = [ 548 ];
  services.netatalk = {
    enable = true;
    volumes = {
      timemachine = {
        path = "/mnt/timemachine";
        "time machine" = "yes";
        "hosts allow" = "192.168.23.0/24";
      };
    };
  };
}
