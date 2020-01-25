{ config, lib, pkgs, boot, networking, containers, ... }:

{

  containers.unifi = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

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
        openPorts = true;
        unifiPackage = pkgs.unifiStable;
      };
    };
  };
}
