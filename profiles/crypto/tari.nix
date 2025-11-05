{
  config,
  lib,
  pkgs,
  ...
}: {
  fileSystems."/var/lib/tari" = {
    device = "pool3d/root/tari";
    fsType = "zfs";
    options = ["nofail" "sync=disabled"];
  };

  services.tari = {
    enable = true;
    network = "mainnet";
    dataDir = "/var/lib/tari";
    openFirewall = true;
  };
}
