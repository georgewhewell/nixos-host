{ config, pkgs, ... }:

{
  # Config for machines on home network
  environment.systemPackages = [ pkgs.jq ];

  security.acme.certs."elk.satanic.link" = {
     email = "georgerw@gmail.com";
     extraDomains = { "es.satanic.link" = null; };
     postRun = ''systemctl reload nginx.service'';
  };

  services.nginx.virtualHosts."elk.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:5601";
    };
  };

  services.nginx.virtualHosts."es.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:9200";
    };
  };

  services.kibana = {
    enable = true;
    listenAddress = "127.0.0.1";
  };

  fileSystems."/var/lib/elasticsearch" =
    { device = "bpool/root/elk";
      fsType = "zfs";
    };

  services.elasticsearch = {
    enable = true;
    listenAddress = "127.0.0.1";
  };

  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1:9090";
    scrapeConfigs = [{
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
          "127.0.0.1:9100"
          "192.168.23.1:9100"
          "nixhost.4a:9100"
          "fuckup.4a:9100"
          "jetson-tx1.4a:9100"
          "odroid-c2.4a:9100"
          "nanopi-neo.4a:9100"
          "nanopi-neo2.4a:9100"
          "pine64-pine64.4a:9100"
          "orangepi-plus2e.4a:9100"
          "orangepi-pc2.4a:9100"
          "orangepi-prime.4a:9100"
          "orangepi-zero.4a:9100"
          "rock64.4a:9100"
          "x3399.4a:9100"
        ];
        labels = {};
      }];
    }];
  };

}
