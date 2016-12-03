{ config, lib, pkgs, boot, networking, containers, ... }:

{
  containers.unifi = {

    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

    config = {
      boot.isContainer = true;

      networking.hostName = "unifi";
      networking.firewall.allowedTCPPorts = [ 8443 ];

      networking.interfaces.eth0.useDHCP = true;

      services.avahi.nssmdns = true;
      services.avahi.enable = true;
      services.avahi.publish.enable = true;

      nixpkgs.config.allowUnfree = true;
      services.unifi.enable = true;
    };
  };
}
