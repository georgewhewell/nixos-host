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
          "router.lan:9100"
          "nixhost.lan:9100"
          "fuckup.lan:9100"
        ];
        labels = {};
      }];
    }];
  };

}
