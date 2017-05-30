{ config, lib, pkgs, boot, networking, containers, ... }:

{
  networking.firewall.allowedTCPPorts = [ 5050 ];

  fileSystems."/var/lib/plex" =
    { device = "fpool/root/config/plex";
      fsType = "zfs";
    };

  containers.plex = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

    bindMounts = {
      "/var/lib/plex" = {
        hostPath = "/var/lib/plex";
        isReadOnly = false;
      };
      "/movies" = {
        hostPath = "/mnt/Media/Movies";
        isReadOnly = false;
      };
      "/tv" = {
        hostPath = "/mnt/Media/TV";
        isReadOnly = false;
      };
      "/misc" = {
       hostPath = "/mnt/Media/Serve";
       isReadOnly = false;
      };
    };

    config = {
      boot.isContainer = true;

      networking.hostName = "plex";
      networking.firewall.enable = false;
      networking.interfaces.eth0.useDHCP = true;

      nixpkgs.config.allowUnfree = true;

      services.plex = {
        enable = true;
        dataDir = "/var/lib/plex";
      };
    };
  };
}
