{config, ...}: {
  # ZFS filesystem for p2pool data
  fileSystems."/var/lib/p2pool" = {
    device = "zpool/root/p2pool";
    fsType = "zfs";
    options = ["nofail" "sync=disabled"];
  };

  services.p2pool = {
    enable = true;
    mini = false;
    host = "192.168.23.8";
    rpcPort = 18081;
    zmqPort = 18083;
    walletAddress = "4878JKf387qCg1dT6Gs1wERmosrTqxtUR185xeMXpTW3f9TRkM6vD5dHABzULx5DTDZFC9XcdQ1nW3ZksvNp34pVBmNCEfm";
    dataDir = "/var/lib/p2pool";
    openFirewall = false;
  };

  # Enable p2pool-exporter
  services.p2pool-exporter = {
    enable = true;
    p2poolApiUrl = "https://p2pool.observer";
    walletAddresses = [config.services.p2pool.walletAddress];
    logLevel = "INFO";
    exchangeRates = ["USD"];
  };

  # Ensure p2pool starts after ZFS mount
  systemd.services.p2pool.unitConfig.RequiresMountsFor = [config.services.p2pool.dataDir];
}
