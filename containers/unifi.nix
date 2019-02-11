{ config, lib, pkgs, boot, networking, containers, ... }:

{

  containers.unifi = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br.lan";

    bindMounts = {
      "/var/lib/unifi/data" = {
        hostPath = "/var/lib/unifi/data";
        isReadOnly = false;
      };
    };

    config = {
      boot.isContainer = true;

      networking.hostName = "unifi.lan";
      networking.interfaces.eth0.useDHCP = true;
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [ 443 8443 ];
        extraCommands = ''
          ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443
          ${pkgs.iptables}/bin/iptables -t nat -A OUTPUT -o lo -p tcp --dport 443 -j REDIRECT --to-port 8443
        '';
      };

      nixpkgs.config.allowUnfree = true;
      services.unifi.enable = true;
    };
  };
}
