{ config, pkgs, ... }:

{

  fileSystems."/var/lib/workvm" =
    {
      device = "zpool/root/workvm";
      fsType = "zfs";
    };

  containers.workvm = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

    bindMounts = {
      "/var/lib/workvm" = {
        hostPath = "/home/grw";
        isReadOnly = false;
      };
    };

    config = {
      boot.isContainer = true;

      imports = [
        ../profiles/common.nix
        ../profiles/home.nix
        ../profiles/development.nix
        ../profiles/graphical.nix
        ../profiles/home-manager.nix
      ];

      networking = {
        hostName = "workvm";
        firewall.allowedTCPPorts = [ 5900 ];
        enableIPv6 = false;
        interfaces.eth0 = {
          useDHCP = true;
        };
      };
    };

  };

}
