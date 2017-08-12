{ config, lib, pkgs, boot, networking, containers, ... }:

{
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
      "/mnt/Media" = {
        hostPath = "/mnt/Media";
        isReadOnly = false;
      };
    };

    config = {
      boot.isContainer = true;
      time.timeZone = "Europe/London";

      networking.hostName = "sonarr";
      networking.firewall = {
        enable = false;
        extraCommands = ''
          ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8989
          ${pkgs.iptables}/bin/iptables -t nat -A OUTPUT -o lo -p tcp --dport 80 -j REDIRECT --to-port 8989
        '';
      };
      networking.interfaces.eth0.useDHCP = true;
      services.sonarr.enable = true;
    };
  };
}
