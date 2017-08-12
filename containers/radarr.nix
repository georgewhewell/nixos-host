{ config, lib, pkgs, boot, networking, containers, ... }:

{
  fileSystems."/var/lib/radarr" =
    { device = "fpool/root/config/radarr";
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
      boot.isContainer = true;

      networking.hostName = "radarr";
      networking.interfaces.eth0.useDHCP = true;
      networking.firewall.allowedTCPPorts = [ 7878 ];
      time.timeZone = "Europe/London";


      systemd.services.radarr = {
      description = "Radarr";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      preStart = ''
        test -d /var/lib/radarr/ || {
          echo "Creating radarr data directory in /var/lib/radarr/"
          mkdir -p /var/lib/radarr/
        }
        chown -R radarr /var/lib/radarr/
        chmod 0700 /var/lib/radarr/
      '';

      serviceConfig = {
        Type = "simple";
        User = "radarr";
        Group = "nogroup";
        PermissionsStartOnly = "true";
        ExecStart = "${pkgs.radarr}/bin/Radarr";
        Restart = "on-failure";
      };
    };

    users.extraUsers.radarr = {
      home = "/var/lib/radarr";
      group = "radarr";
    };

    };
  };
}
