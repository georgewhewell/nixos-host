{ config, lib, pkgs, boot, networking, containers, ... }:

{
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
      "/mnt/Media" = {
        hostPath = "/mnt/Media";
        isReadOnly = false;
      };
    };

    config = {
      boot.isContainer = true;
      networking.hostName = "couchpotato";
      networking.firewall = {
        enable = false;
        allowedTCPPorts = [ 80 5050 ];
        extraCommands = ''
          ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 5050
          ${pkgs.iptables}/bin/iptables -t nat -A OUTPUT -o lo -p tcp --dport 80 -j REDIRECT --to-port 5050
        '';
      };
      networking.interfaces.eth0.useDHCP = true;
      environment.systemPackages = with pkgs; [
        python27Packages.python
        python27Packages.sqlite3
        python27Packages.lxml
        unrar
        par2cmdline
      ];

      systemd.services.couchpotato = {
        wantedBy = [ "multi-user.target" ];
        environment = {
          PYTHONPATH = "${pkgs.python27Packages.sqlite3}/lib/python2.7/site-packages:${pkgs.python27Packages.lxml}/lib/python2.7/site-packages";
        };
        serviceConfig = {
          Restart = "always";
          ExecStart = ''
            ${pkgs.python27Packages.python}/bin/python ${pkgs.couchpotato}/CouchPotato.py --data /var/lib/couchpotato
          '';
        };
      };
    };
  };
}
