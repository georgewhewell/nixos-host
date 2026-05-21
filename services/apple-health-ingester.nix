{config, network, ...}: {
  services.apple-health-ingester = {
    enable = true;
    listenAddress = "${network.primaryIp network.hosts.trex}:8085";
    dataDir = "/var/lib/apple-health-ingester";
    backends.localfile.enable = true;
    backends.influxdb = {
      enable = true;
      url = "http://127.0.0.1:8428";
      org = "default";
      bucket = "apple_health";
    };
  };

  fileSystems."/var/lib/apple-health-ingester" = {
    device = "pool3d/root/apple-health-ingester";
    fsType = "zfs";
    options = ["nofail"];
  };
}
