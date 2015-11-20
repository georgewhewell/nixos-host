{ config, lib, pkgs, ... }:

{
  services.tinc.networks."darknet" = {
    hosts = {
      tsar_su = ''
        Address = tsar.su
        Ed25519PublicKey = /hjseAhOR1tAiittJSgwO4lFG8yO42Pq9rXHfeF47ZN
        Subnet 10.0.0.1/32
      '';
      nixhost = ''
        Address = 86.3.184.2
        Ed25519PublicKey = GC1+3QeMQZwvuRKFsHUd8Mw6vKbCl3uG66M6xGqhXwB
        Subnet 10.0.0.2/32
      '';
    };
    extraConfig = ''
      ConnectTo tsar_su
    '';
  };
  networking.firewall.allowedUDPPorts = [ 655 ];
}
