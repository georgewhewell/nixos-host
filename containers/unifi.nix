{ config, lib, pkgs, boot, networking, containers, ... }:

{

  fileSystems."/var/lib/unifi" =
    {
      device = "nvpool/root/configs/unifi";
      fsType = "zfs";
      options = [ "nofail" ];
    };

  containers.unifi = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0.lan";

    bindMounts = {
      "/var/lib/unifi" = {
        hostPath = "/var/lib/unifi";
        isReadOnly = false;
      };
    };

    config = {
      imports = [ ../profiles/container.nix ];

      networking.hostName = "unifi";
      networking.firewall.allowedTCPPorts = [ 443 8443 ];

      services.unifi = {
        enable = true;
        openFirewall = true;
        unifiPackage = pkgs.unifi8;
        mongodbPackage = pkgs.mongodb-5_0;
      };
    };
  };
}
