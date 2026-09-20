{
  config,
  pkgs,
  lib,
  mkSecret,
  network,
  ...
}: let
  trexIp = network.primaryIp network.hosts.trex;
  bluefield2Ip = network.primaryIp network.hosts.bluefield2;
  nodeHosts = [
    "router"
    "trex"
    "rock-5b"
    "k3"
    "bluefield2"
    "n100"
    "strix-1"
    "strix-2"
    "strix-3"
    "strix-4"
    "fuckup"
    # Macs run prometheus-node-exporter on :9100 (darwin subset of collectors).
    "goblin"
    "mbp"
  ];
  x86ExporterHosts = [
    "router"
    "trex"
    "n100"
    "strix-1"
    "strix-2"
    "strix-3"
    "strix-4"
    "fuckup"
  ];
  cadvisorHosts = [
    "router"
    "trex"
  ];
  mtailHosts = [
    "router"
    "trex"
    "n100"
    # xmrig miners run mtail (xmrig log parser) — scrape their hashrate/share metrics.
    "fuckup"
    "strix-1"
    "strix-2"
    "strix-3"
    "strix-4"
    # Macs export the same xmrig_* metrics via a small HTTP exporter on :3903
    # (no journald/mtail on darwin).
    "goblin"
    "mbp"
  ];
  # The benchmark harness runs only rank 0 as an OpenAI API server. USB4
  # scenarios use strix-1, while CX-5 and retained interactive scenarios use
  # strix-4; the remaining ranks are headless workers with no metrics endpoint.
  vllmApiHosts = [
    "strix-1"
    "strix-4"
  ];
  # Shared scrape configs used by both Prometheus and VictoriaMetrics
  # This allows running both in parallel during migration
  scrapeConfigs = [
    {
      job_name = "node";
      static_configs = [
        {
          targets = map (host: "${host}:9100") nodeHosts;
        }
      ];
    }
    {
      # BlueField VPP statseg telemetry. Keep this separate from node metrics
      # so dashboard queries can select the dataplane without double-counting
      # the bf0 parent and its VLAN subinterfaces.
      job_name = "vpp";
      scrape_interval = "15s";
      scrape_timeout = "10s";
      static_configs = [
        {
          # The BlueField hostname has LAN, fabric, and private-DPU records.
          # Scrape the source-restricted LAN listener deterministically.
          targets = ["${bluefield2Ip}:9482"];
          labels = {
            instance = "bluefield2";
            site = "bluefield2";
            dataplane = "vpp";
          };
        }
      ];
    }
    {
      # OpenWrt devices: prometheus-node-exporter-lua on :9100. The UniFi AP
      # also has wifi/wifi_stations collectors.
      job_name = "openwrt";
      scrape_timeout = "10s";
      static_configs = [
        {
          targets = [
            "unifi-ac-pro:9100"
            "10g-onti:9100"
          ];
        }
      ];
    }
    {
      job_name = "cadvisor";
      static_configs = [
        {
          targets = map (host: "${host}:${builtins.toString config.services.cadvisor.port}") cadvisorHosts;
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
          targets = map (host: "${host}:3903") mtailHosts;
        }
      ];
    }
    {
      job_name = "vllm";
      scrape_interval = "5s";
      scrape_timeout = "4s";
      static_configs = [
        {
          targets = map (host: "${host}:8000") vllmApiHosts;
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
          targets = map (host: "${host}:${builtins.toString config.services.prometheus.exporters.smartctl.port}") x86ExporterHosts;
        }
      ];
    }
    {
      job_name = "zfs";
      static_configs = [
        {
          targets = map (host: "${host}:${builtins.toString config.services.prometheus.exporters.zfs.port}") x86ExporterHosts;
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
      job_name = "llm-quota";
      static_configs = [
        {
          targets = ["trex:9184"];
        }
        {
          targets = ["fuckup:9184"];
        }
      ];
      metric_relabel_configs = [
        {
          source_labels = ["instance" "provider"];
          regex = "trex:9184;openai";
          target_label = "provider";
          replacement = "openai-company";
        }
        {
          source_labels = ["instance" "provider"];
          regex = "fuckup:9184;openai";
          target_label = "provider";
          replacement = "openai-personal";
        }
      ];
    }
    {
      # llama.cpp on mbp (Muse-Glimmer-30B). llama-server serves its Prometheus
      # metrics from the same port as the API, so this is :8080/metrics rather
      # than a sidecar exporter. Gives prompt/generation tokens per second, KV
      # cache utilisation and queue depth.
      job_name = "llama-cpp";
      static_configs = [
        {
          targets = ["mbp:8080"];
        }
      ];
    }
    {
      # gpsd on k3: per-satellite SNR/elevation/azimuth, satellites seen vs
      # used, fix mode. k3 is the only host with a receiver on a real UART.
      job_name = "gpsd";
      static_configs = [
        {
          targets = ["k3:9015"];
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
      static_configs = map (host: {
        targets = ["${network.primaryIp network.hosts.${host}}:9400"];
        labels.instance = host;
      }) [ "strix-4" ];
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
          # The target string becomes the `instance` label, so renaming these
          # starts fresh series; the pre-2026-08-15 history stays under the
          # old mikrotik-10g / mikrotik-100g instance names.
          targets = [
            "mikrotik-crs210"
            "mikrotik-crs510"
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

  # Override systemd service to use our ZFS-managed mount.
  systemd.services.victoriametrics = {
    after = ["zfs-mount.service"];
    wants = ["zfs-mount.service"];
    serviceConfig = {
      # Disable DynamicUser since we're using a custom storage path
      DynamicUser = lib.mkForce false;
      User = "victoriametrics";
      Group = "victoriametrics";
      # Remove StateDirectory since we manage storage ourselves
      StateDirectory = lib.mkForce "";
    };
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
