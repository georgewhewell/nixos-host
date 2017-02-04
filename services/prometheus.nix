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
      - targets: ['nixhost.4a:9100', 'fuckup.4a:9100']
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

  systemd.services.prometheus = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.prometheus}/bin/prometheus \
        -config.file "${configFile}"'';
    };
  };

  systemd.services.prometheus-node-exporter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.prometheus-node-exporter}/bin/node_exporter
      '';
    };
  };

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
  
  systemd.services.prometheus-ipmi-exporter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.prometheus-ipmi-exporter}/bin/ipmi_exporter \
        -ipmi.path "${pkgs.ipmitool}/bin/ipmitool"
      '';
    };
  };


}
