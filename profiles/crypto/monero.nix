{config, ...}: {
  # monero
  fileSystems."/var/lib/monero" = {
    device = "pool3d/root/monero";
    fsType = "zfs";
    options = ["nofail" "sync=disabled"];
  };

  services.monero = {
    enable = true;
    dataDir = "/var/lib/monero";
    rpc = {
      address = "192.168.23.8";
    };
    extraConfig = ''
      confirm-external-bind=1
    '';
  };

  networking.firewall.allowedTCPPorts = [18080 18081];

  systemd.services.monero.unitConfig.RequiresMountsFor = [config.services.monero.dataDir];
}
