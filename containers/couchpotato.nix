{ config, lib, pkgs, boot, networking, containers, ... }:

{
  networking.firewall.allowedTCPPorts = [ 5050 ];

  fileSystems."/var/lib/couchpotato" =
    { device = "fpool/root/config/couchpotato";
      fsType = "zfs";
    };

  containers.couchpotato = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

    bindMounts = {
      "/var/lib/couchpotato" = {
        hostPath = "/var/lib/couchpotato";
        isReadOnly = false;
      };
      "/downloads" = {
        hostPath = "/mnt/Media/downloads";
        isReadOnly = false;
      };
      "/movies" = {
        hostPath = "/mnt/Media/Movies";
        isReadOnly = false;
      };
    };

    config = {
      boot.isContainer = true;

      networking.hostName = "couchpotato";
      networking.firewall.enable = false;
      networking.interfaces.eth0.useDHCP = true;

      systemd.services.couchpotato = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = ''
            ${pkgs.python}/bin/python ${pkgs.couchpotato}/CouchPotato.py --data /var/lib/couchpotato
          '';
        };
      };
    };
  };
}
