{config, mkSecret, ...}: {
  sops.secrets.p2pool-env = mkSecret "p2pool-env" {};

  # ZFS filesystem for p2pool data
  fileSystems."/var/lib/p2pool" = {
    device = "pool3d/root/p2pool";
    fsType = "zfs";
    options = ["nofail" "sync=disabled"];
  };

  # Create data-api directory
  systemd.tmpfiles.rules = [
    "d /var/lib/p2pool/data-api 0755 p2pool p2pool - -"
  ];

  services.p2pool = {
    enable = true;
    mini = false;
    host = "127.0.0.1";
    rpcPort = 18081;
    zmqPort = 18083;
    walletAddress = "45M3DBgTqc9jd8TwmvtZbg7v5pKjsgckzgUENPkXVwD8QURYoVkXQPQ3YJMjtYKaqgExxrFe5T2Li8cosfN82xWGSsLyJwa";
    dataDir = "/var/lib/p2pool";
    openFirewall = true;
    extraArgs = ["--data-api" "/var/lib/p2pool/data-api"];
    environmentFile = config.sops.secrets.p2pool-env.path;
    mergeMining = {
      enable = true;
      tariHost = "127.0.0.1";
      tariPort = 18142;
      tariWalletAddress = "$TARI_WALLET_ADDRESS";
    };
  };

  # Enable p2pool-exporter
  services.p2pool-exporter = {
    enable = true;
    p2poolApiUrl = "https://p2pool.observer";
    walletAddresses = [config.services.p2pool.walletAddress];
    logLevel = "INFO";
    exchangeRates = ["USD"];
  };

  services.redis.servers.p2pool = {
    bind = "127.0.0.1";
    port = 6379;
  };

  # Ensure p2pool starts after its local merge-mining dependencies are ready.
  systemd.services.p2pool = {
    unitConfig.RequiresMountsFor = [config.services.p2pool.dataDir];
    after = ["sops-nix.service" "monero.service" "podman-tari.service" "network-online.target"];
    wants = ["monero.service" "podman-tari.service" "network-online.target"];
  };
}
