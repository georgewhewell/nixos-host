{ config, lib, pkgs, boot, networking, containers, ... }:

{

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
    };

    config = {
      boot.isContainer = true;

      networking.hostName = "plex";

      networking.firewall.enable = true;
      networking.firewall.allowedUDPPorts = [ 1900 5353
        32410 32412 32413 32414];
      networking.firewall.allowedTCPPorts = [ 32400 32469 ];

      networking.interfaces.eth0.useDHCP = true;

      nixpkgs.config.allowUnfree = true;

      services.plex = {
        enable = true;
        dataDir = "/var/lib/plex";
      };
    };
  };
}
