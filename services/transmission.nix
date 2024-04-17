{ config, lib, pkgs, ... }:
let
  incompleteDir = "/mnt/downloads";
in
{
  fileSystems.${incompleteDir} =
    {
      device = "nvpool/root/incomplete";
      fsType = "zfs";
      options = [ "nofail" ];
    };

  services.transmission = {
    enable = true;
    openFirewall = true;
    settings = {
      download-dir = "/mnt/Media/downloads";
      download-queue-size = 8;
      incomplete-dir = incompleteDir;
      incomplete-dir-enabled = true;
      rpc-whitelist-enabled = false;
      rpc-whitelist = "127.0.0.1,192.168.0.*,192.168.23.*,192.168.24.*";
      rpc-host-whitelist = "nixhost.lan";
      rpc-bind-address = "0.0.0.0";
      cache-size-mb = 1024;
      scrape-paused-torrents-enabled = false;
      seed-queue-enabled = true;
      seed-queue-size = 10000;
      speed-limit-up-enabled = false;
      umask = 2;
    };
  };

  networking.firewall.allowedTCPPorts = [ 51413 ];
  networking.firewall.allowedUDPPorts = [ 51413 ];
}
