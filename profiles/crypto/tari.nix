{
  config,
  lib,
  pkgs,
  network,
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
    extraArgs = [
      "-p"
      "base_node.p2p.transport.type=tcp"
      "-p"
      "base_node.p2p.transport.tcp.listener_address=/ip4/0.0.0.0/tcp/18141"
      "-p"
      "base_node.p2p.transport.tcp.tor_socks_address=/ip4/${network.routerIp}/tcp/9050"
      "-p"
      "base_node.p2p.dht.num_neighbouring_nodes=24"
      "-p"
      "base_node.p2p.dht.num_random_nodes=24"
      "-p"
      "base_node.p2p.max_concurrent_inbound_tasks=400"
      "-p"
      "base_node.p2p.max_concurrent_outbound_tasks=400"
      "-p"
      "base_node.state_machine.blockchain_sync_config.validation_concurrency=24"
    ];
  };
}
