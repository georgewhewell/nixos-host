{ config, pkgs, ... }:
{

  # monero
  fileSystems."/var/lib/monero" =
    {
      device = "nvpool/root/monero";
      fsType = "zfs";
      options = [ "nofail" "sync=disabled" ];
    };

  services.monero = {
    enable = true;
    dataDir = "/var/lib/monero";
    rpc = {
      address = "192.168.23.5";
    };
    extraConfig = ''
      confirm-external-bind=1
    '';
  };

  systemd.services.monero.unitConfig.RequiresMountsFor = [ config.services.monero.dataDir ];

}
