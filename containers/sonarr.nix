{ config, lib, pkgs, boot, networking, containers, ... }:

{
  fileSystems."/var/lib/sonarr" =
    {
      device = "fpool/root/config/sonarr";
      fsType = "zfs";
    };

  containers.sonarr = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

    bindMounts = {
      "/var/lib/sonarr" = {
        hostPath = "/var/lib/sonarr";
        isReadOnly = false;
      };
      "/mnt/Media" = {
        hostPath = "/mnt/Media";
        isReadOnly = false;
      };
    };

    config = {
      imports = [ ../profiles/container.nix ];

      networking.hostName = "sonarr";
      networking.firewall.allowedTCPPorts = [ 8989 ];

      services.sonarr.enable = true;
    };
  };
}
