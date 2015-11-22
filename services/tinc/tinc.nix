{ config, lib, pkgs, ... }:

{
  services.tinc.networks."darknet" = {
    debugLevel = 5;
    hosts = {
      tsar_su = ''
        Address = tsar.su
        Ed25519PublicKey = /hjseAhOR1tAiittJSgwO4lFG8yO42Pq9rXHfeF47ZN
        Subnet 10.0.0.1
      '';
      nixhost = ''
        Ed25519PublicKey = GC1+3QeMQZwvuRKFsHUd8Mw6vKbCl3uG66M6xGqhXwB
        Subnet 10.0.0.2
      '';
    };
    extraConfig = ''
      ConnectTo tsar_su
    '';
  };
  networking.firewall.allowedUDPPorts = [ 655 ];
}
