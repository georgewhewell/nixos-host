{ config, lib, pkgs, boot, networking, containers, ... }:

{

  fileSystems."/var/lib/unifi" =
    { device = "fpool/root/config/unifi";
      fsType = "zfs";
    };

  containers.unifi = {

    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

    bindMounts = {
      "/var/lib/unifi/data" = {
        hostPath = "/var/lib/unifi/data";
        isReadOnly = false;
      };
    };

    config = {
      boot.isContainer = true;

      networking.hostName = "unifi";
      networking.interfaces.eth0.useDHCP = true;
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [ 443 8443 ];
        extraCommands = ''
          ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443
        '';
      };

      nixpkgs.config.allowUnfree = true;
      services.unifi.enable = true;

    };
  };
}
