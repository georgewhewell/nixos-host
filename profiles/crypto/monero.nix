{config, ...}: {
  # monero
  fileSystems."/var/lib/monero" = {
    # Moved off bpool's HDD stripe onto the nand4 NVMe array (2026-08-11).
    # These are random-IO chain databases; the HDDs are why they were parked.
    #
    # No btrfs equivalent of the ZFS sync=disabled these datasets used to
    # carry, and deliberately no commit= override: btrfs applies commit,
    # flushoncommit, compress, ssd and discard FILESYSTEM-wide, set by
    # whichever mount comes first. Loosening durability for the chains would
    # therefore also loosen it for /mnt/Home and /nix, which share this array.
    # The relaxation lives in monerod's own LMDB sync mode instead.
    device = "/dev/disk/by-label/nand4";
    fsType = "btrfs";
    options = ["subvol=/chains/monero" "compress=zstd" "noatime" "nofail"];
  };

  services.monero = {
    enable = true;
    dataDir = "/var/lib/monero";
    rpc = {
      address = "0.0.0.0";
      restricted = false;
    };
    priorityNodes = [
      "p2pmd.xmrvsbeast.com:18080"
      "nodes.hashvault.pro:18080"
    ];
    extraConfig = ''
      # The chain is fully re-downloadable, so durability here buys nothing.
      # This is the real equivalent of the ZFS sync=disabled these datasets
      # used to carry (btrfs has no such mount option): LMDB stops fsyncing
      # every batch and only flushes every ~250MB, which also speeds up the
      # catch-up sync substantially.
      db-sync-mode=fastest:async:250000000bytes
      no-igd=1
      out-peers=64
      in-peers=64
      confirm-external-bind=1
      zmq-pub=tcp://0.0.0.0:18083
    '';
  };

  networking.firewall.allowedTCPPorts = [
    18080 # Monero P2P
    18081 # Monero RPC
  ];

  networking.firewall.allowedUDPPorts = [
    18080 # Monero P2P
  ];

  systemd.services.monero.unitConfig.RequiresMountsFor = [config.services.monero.dataDir];
}
