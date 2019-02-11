{ config, pkgs, ... }:

{
  # Config for machines on home network
  environment.systemPackages = [ pkgs.jq ];

  fileSystems."/var/lib/elasticsearch" =
    { device = "bpool/root/elk";
      fsType = "zfs";
    };

  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1:9090";
    exporters = {
      unifi = {
        enable = true;
        unifiAddress = "https://unifi.lan:8443";
        unifiInsecure = true;
        unifiUsername = "ReadOnlyUser";
        unifiPassword = "ReadOnlyUser";
      };
    };
    scrapeConfigs = [
    {
      job_name = "bot";
      scrape_interval = "1s";
      static_configs = [{
        targets = [ "fuckup.4a:50010" ];
        labels = {};
      }];
    }
    {
      job_name = "nginx";
      scrape_interval = "5s";
      static_configs = [{
        targets = [ "127.0.0.1:9113" ];
        labels = {};
      }];
    }
    {
      job_name = "unifi";
      scrape_interval = "5s";
      static_configs = [{
        targets = [ "127.0.0.1:9130" ];
        labels = {};
      }];
    }
    {
      job_name = "prometheus";
      scrape_interval = "5s";
      static_configs = [{
        targets = [ "127.0.0.1:9090" ];
        labels = {};
      }];
    }{
      job_name = "node";
      scrape_interval = "5s";
      static_configs = [{
        targets = [
          "router.4a:9100"
          "nixhost.4a:9100"
          "fuckup.4a:9100"
          "hydra.4a:9100"
          "airport.4a:9100"
          "jetson-tx1.4a:9100"
          "odroid-c2.4a:9100"
          "nanopi-m3.4a:9100"
          "nanopi-duo.4a:9100"
          "nanopi-neo2.4a:9100"
          "pine64-pine64.4a:9100"
          "pine64-h64:9100"
          "orangepi-plus2e.4a:9100"
          "orangepi-pc2.4a:9100"
          "orangepi-prime.4a:9100"
          "orangepi-zero.4a:9100"
          "rock64.4a:9100"
        ];
        labels = {};
      }];
    }];
  };

}
