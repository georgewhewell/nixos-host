{
  config,
  pkgs,
  lib,
  mkSecret,
  network,
  ...
}: let
  trexIp = network.primaryIp network.hosts.trex;
  # Shared scrape configs used by both Prometheus and VictoriaMetrics
  # This allows running both in parallel during migration
  scrapeConfigs = [
    {
      job_name = "node";
      static_configs = [
        {
          targets = [
            "nixhost:9100"
            "router:9100"
            "trex:9100"
            "rock-5b:9100"
            "n100:9100"
            "prime:9100"
            "neo2:9100"
            "strix-1:9100"
            "strix-2:9100"
            "fuckup:9100"
          ];
        }
      ];
    }
    {
      job_name = "cadvisor";
      static_configs = [
        {
          targets = [
            "nixhost:58080"
            "router:58080"
            "trex:58080"
            "n100:58080"
          ];
        }
      ];
    }
    {
      job_name = "nginx";
      static_configs = [
        {
          targets = ["127.0.0.1:9113"];
        }
      ];
    }
    {
      job_name = "mtail";
      static_configs = [
        {
          targets = [
            "router:3903"
            "trex:3903"
            "fuckup:3903"
            "rock-5b:3903"
            "n100:3903"
            "strix-1:3903"
            "strix-2:3903"
          ];
        }
      ];
    }
    {
      job_name = "unifi";
      static_configs = [
        {
          targets = ["127.0.0.1:9130"];
        }
      ];
    }
    {
      job_name = "victoriametrics";
      static_configs = [
        {
          targets = ["127.0.0.1:8428"];
        }
      ];
    }
    {
      job_name = "postgres";
      static_configs = [
        {
          targets = ["127.0.0.1:9187"];
        }
      ];
    }
    {
      job_name = "ipmi";
      static_configs = [
        {
          targets = ["127.0.0.1:9290"];
        }
      ];
    }
    {
      job_name = "dnsmasq";
      static_configs = [
        {
          targets = ["${network.routerIp}:9153"];
        }
      ];
    }
    {
      job_name = "smartctl";
      static_configs = [
        {
          targets = [
            "trex:${builtins.toString config.services.prometheus.exporters.smartctl.port}"
            "nixhost:${builtins.toString config.services.prometheus.exporters.smartctl.port}"
          ];
        }
      ];
    }
    {
      job_name = "zfs";
      static_configs = [
        {
          targets = [
            "trex:${builtins.toString config.services.prometheus.exporters.zfs.port}"
            "router:${builtins.toString config.services.prometheus.exporters.zfs.port}"
          ];
        }
      ];
    }
    {
      job_name = "lighthouse";
      static_configs = [
        {
          targets = ["${trexIp}:5054"];
        }
      ];
    }
    {
      job_name = "reth";
      static_configs = [
        {
          targets = ["${trexIp}:6060"];
        }
      ];
    }
    {
      job_name = "p2pool";
      static_configs = [
        {
          targets = ["router:8889"];
        }
      ];
    }
    {
      job_name = "tari";
      static_configs = [
        {
          targets = ["trex:5577"];
        }
      ];
    }
    {
      job_name = "home-assistant";
      metrics_path = "/api/prometheus";
      authorization = {
        credentials_file = "/run/secrets/hass-prometheus-token";
      };
      static_configs = [
        {
          targets = ["router:8123"];
        }
      ];
    }
    {
      job_name = "hostapd";
      static_configs = [
        {
          targets = ["router:9551"];
        }
      ];
    }
    {
      job_name = "nut";
      metrics_path = "/ups_metrics";
      static_configs = [
        {
          targets = ["127.0.0.1:9199"];
        }
      ];
    }
    {
      job_name = "hellas-node";
      scrape_interval = "10s";
      static_configs = [
        {
          targets = ["fuckup:9400"];
        }
      ];
    }
    {
      job_name = "apcupsd";
      static_configs = [
        {
          targets = ["127.0.0.1:${toString config.services.prometheus.exporters.apcupsd.port}"];
        }
      ];
    }
    {
      job_name = "snmp";
      metrics_path = "/snmp";
      params = {module = ["if_mib"];};
      relabel_configs = [
        {
          source_labels = ["__address__"];
          target_label = "__param_target";
        }
        {
          source_labels = ["__param_target"];
          target_label = "instance";
        }
        {
          source_labels = [];
          target_label = "__address__";
          replacement = "localhost:9116";
        }
      ];
      static_configs = [
        {
          targets = [
            "mikrotik-10g"
            "mikrotik-100g"
            (network.fqdn "apc8b3fcb")
          ];
        }
      ];
    }
  ];
in {
  # Reuse the hass token secret (already declared in logserver.nix)
  # sops.secrets.hass-prometheus-token = mkSecret "hass-prometheus-token" {};

  services.victoriametrics = {
    enable = true;
    listenAddress = "127.0.0.1:8428";
    # 100 years retention - effectively forever
    retentionPeriod = "100y";
    prometheusConfig = {
      scrape_configs = scrapeConfigs;
    };
    extraOptions = [
      # Use ZFS volume for data storage (mounted at /mnt/victoriametrics)
      "-storageDataPath=/mnt/victoriametrics"
      # Disable check since secrets aren't available at build time
      "-promscrape.config.strictParse=false"
      # Enable deduplication for HA data (useful if scraping same source)
      "-dedup.minScrapeInterval=15s"
      # Better compression
      "-storage.minFreeDiskSpaceBytes=1GB"
    ];
  };

  # Override systemd service to use our ZFS mount
  systemd.services.victoriametrics.serviceConfig = {
    # Disable DynamicUser since we're using a custom storage path
    DynamicUser = lib.mkForce false;
    User = "victoriametrics";
    Group = "victoriametrics";
    # Remove StateDirectory since we manage storage ourselves
    StateDirectory = lib.mkForce "";
  };

  users.users.victoriametrics = {
    isSystemUser = true;
    group = "victoriametrics";
    home = "/mnt/victoriametrics";
    extraGroups = [];
  };
  users.groups.victoriametrics = {};

  # Ensure the mount point has correct ownership
  systemd.tmpfiles.rules = [
    "d /mnt/victoriametrics 0750 victoriametrics victoriametrics -"
  ];

  # Expose VictoriaMetrics through nginx for Grafana access
  services.nginx.virtualHosts.${network.publicFqdn "grafana"} = {
    locations."/victoria/" = {
      proxyPass = "http://127.0.0.1:8428/";
    };
  };
}
