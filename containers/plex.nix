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
      imports = [ ../profiles/container.nix ];

      networking.hostName = "plex";
      networking.firewall = {
        enable = true;
        checkReversePath = false;
        allowedUDPPorts = [ 1900 5353 32410 32412 32413 32414];
        allowedTCPPorts = [ 32400 32469 ];
      };

      nixpkgs.config.allowUnfree = true;

      services.plex = {
        enable = true;
        dataDir = "/var/lib/plex";
      };
    };
  };
}
