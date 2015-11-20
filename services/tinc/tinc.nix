{ config, lib, pkgs, ... }:

{
  services.tinc.networks."darknet" = {
    package = pkgs.tinc_pre;
    hosts = {
      tsar = ''
        Address = tsar.su
        Ed25519PublicKey = /hjseAhOR1tAiittJSgwO4lFG8yO42Pq9rXHfeF47ZN
      '';
      nixhost = ''
        Address = 86.3.184.2
        Ed25519PublicKey = GC1+3QeMQZwvuRKFsHUd8Mw6vKbCl3uG66M6xGqhXwB
      '';
    };
  };
  networking.firewall.allowedUDPPorts = [ 655 ];
}
