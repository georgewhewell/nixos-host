{ config, lib, pkgs, boot, networking, containers, ... }:

{
  fileSystems."/var/lib/radarr" =
    {
      device = "fpool/root/config/radarr";
      fsType = "zfs";
    };

  containers.radarr = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

    bindMounts = {
      "/var/lib/radarr" = {
        hostPath = "/var/lib/radarr";
        isReadOnly = false;
      };
      "/mnt/Media" = {
        hostPath = "/mnt/Media";
        isReadOnly = false;
      };
    };

    config = {
      imports = [ ../profiles/container.nix ];

      networking.hostName = "radarr";
      networking.firewall.allowedTCPPorts = [ 7878 ];

      services.radarr.enable = true;

    };

  };
}
