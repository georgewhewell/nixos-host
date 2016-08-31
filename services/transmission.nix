{ config, lib, pkgs, ... }:

{
  services.transmission.enable = true;
  services.transmission.settings = {
    rpc-whitelist-enabled = false;
    download-dir = "/mnt/storage/downloads";
    umask = 2;
  };
  networking.firewall.allowedTCPPorts = [ 51413 ];
  networking.firewall.allowedUDPPorts = [ 51413 ];
}
