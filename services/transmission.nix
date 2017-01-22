{ config, lib, pkgs, ... }:

{
  fileSystems."/var/lib/transmission/incomplete" =
    { device = "fpool/root/downloads";
      fsType = "zfs";
    };

  services.transmission.enable = true;
  services.transmission.settings = {
    download-dir = "/mnt/Media/downloads";
    incomplete-dir = "/var/lib/transmission/incomplete";
    incomplete-dir-enabled = true;
    rpc-whitelist = "127.0.0.1,192.168.23.*,192.168.24.*";
    umask = 0;
  };

  networking.firewall.allowedTCPPorts = [ 9091 51413 ];
  networking.firewall.allowedUDPPorts = [ 51413 ];
}
