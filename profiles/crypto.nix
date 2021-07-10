{ config, lib, pkgs, ... }:

{

  fileSystems."/var/lib/openethereum" =
    {
      device = "bpool/root/ethereum";
      fsType = "zfs";
    };

  fileSystems."/var/lib/geth" =
    {
      device = "bpool/root/geth";
      fsType = "zfs";
    };

  services.geth = {
    enable = true;
    unsafeExpose = true;
  };

}
