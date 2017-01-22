{ config, lib, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 5050 ];

  fileSystems."/var/lib/couchpotato" =
    { device = "fpool/root/config/couchpotato";
      fsType = "zfs";
    };

  
}
