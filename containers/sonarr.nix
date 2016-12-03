{ config, lib, pkgs, boot, networking, containers, ... }:

{
  networking.firewall.allowedTCPPorts = [ 5050 ];

  fileSystems."/var/lib/sonarr" =
    { device = "fpool/root/config/sonarr";
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
      "/downloads" = {
        hostPath = "/mnt/Media/downloads";
        isReadOnly = false;
      };
      "/tv" = {
        hostPath = "/mnt/Media/TV";
        isReadOnly = false;
      };
    };

    config = {
      boot.isContainer = true;

      networking.hostName = "sonarr";
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [ 80 8989 ];
        extraCommands = ''
          ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8989
        '';
      };

      networking.interfaces.eth0.useDHCP = true;

      services.sonarr.enable = true;
    };
  };
}
