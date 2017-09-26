{ config, lib, pkgs, ... }:

let configFile = pkgs.writeText "prometheus.yml" ''
global:
  scrape_interval:     15s # By default, scrape targets every 15 seconds.

scrape_configs:
  - job_name: 'prometheus'

    # Override the global default and scrape targets from this job every 5 seconds.
    scrape_interval: 5s

    static_configs:
      - targets: ['127.0.0.1:9090']
      - labels:
          instance: nixhost

  - job_name: 'node'
    static_configs:
      - targets:
        - 'pfsense.4a:9100'
        - 'nixhost.4a:9100'
        - 'fuckup.4a:9100'
        - 'orangepi-plus2e.4a'
    relabel_configs:
      - source_labels: [__param_target__]
        target_label: instance

  - job_name: 'ipmi'
    static_configs:
      - targets: ['nixhost.4a:9289']
    relabel_configs:
      - source_labels: [__param_target__]
        target_label: instance

  - job_name: 'snmp'
    static_configs:
      - targets:
        - 192.168.23.1  # SNMP device.
        - 192.168.23.2
        - 192.168.23.3
    metrics_path: /snmp
    params:
      module: [default]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: 127.0.0.1:9116  # SNMP exporter.
''; in
{

  environment.systemPackages = with pkgs; [
    prometheus
    prometheus-node-exporter
    prometheus-snmp-exporter
    prometheus-ipmi-exporter
    ipmitool
    lm_sensors
  ];
  services.prometheus.enable = true;
  services.prometheus.listenAddress = "127.0.0.1:9090";
  services.prometheus.scrapeConfigs = [
    { job_name = "prometheus";
      scrape_interval = "5s";
      static_configs = [
        {
	  targets = [ "127.0.0.1:9090" ];
	  labels = {};
        }
      ];
    }
    { job_name = "node";
      scrape_interval = "5s";
      static_configs = [
        {
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
        }
      ];
    }
  ];

  services.prometheus.nodeExporter.enable = true;
  services.prometheus.nodeExporter.listenAddress = "127.0.0.1";
  services.prometheus.nodeExporter.port = 9100;

  systemd.services.prometheus-snmp-exporter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.prometheus-snmp-exporter}/bin/snmp_exporter \
        -config.file ${pkgs.prometheus-snmp-exporter.src}/snmp.yml
      '';
    };
  };
  networking.firewall.allowedTCPPorts = [ 9090 9100 ];

  systemd.services.prometheus-ipmi-exporter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = ''
        ${pkgs.kmod}/bin/modprobe ipmi_devintf
        ${pkgs.kmod}/bin/modprobe ipmi_si
      '';
      ExecStart = ''${pkgs.prometheus-ipmi-exporter}/bin/ipmi_exporter \
        -ipmi.path "${pkgs.ipmitool}/bin/ipmitool"
      '';
    };
  };


}
