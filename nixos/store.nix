{ config, lib, pkgs, ... }:

{
  services.nix-serve = {
    enable = true;
    secretKeyFile = "/etc/nix/signing-key.sec";
  };

  networking.firewall.allowedTCPPorts = [ 3000 ];

}
