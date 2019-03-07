{ config, pkgs, ... }:

{
  # Config for machines on home network
  environment.systemPackages = [ pkgs.jq ];

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
        job_name = "consul_discovery";
        consul_sd_configs = [{
          server = "localhost:8500";
          datacenter = "dc1";
          token = null;
          username = null;
          password = null;
          scheme = "http";
          services = [ "node_exporter" ];
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
          "router.lan:9100"
          "nixhost.lan:9100"
          "fuckup.lan:9100"
        ];
        labels = {};
      }];
    }];
  };

}
