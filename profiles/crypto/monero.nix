{config, ...}: {
  # monero
  fileSystems."/var/lib/monero" = {
    device = "bpool/trex/monero";
    fsType = "zfs";
    options = ["nofail" "sync=disabled"];
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
