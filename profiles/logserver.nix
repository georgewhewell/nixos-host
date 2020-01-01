{ config, pkgs, ... }:

{

  environment.systemPackages = with pkgs; [
    ipmitool
    lm_sensors
  ];

  networking.firewall.allowedTCPPorts = [ 9090 9100 ];

  systemd.services.prometheus-ipmi-exporter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStartPre = ''
        ${pkgs.kmod}/bin/modprobe ipmi_devintf ipmi_si
      '';
      ExecStart = ''
        ${pkgs.prometheus-ipmi-exporter}/bin/ipmi_exporter \
          -config.file ${pkgs.prometheus-ipmi-exporter.src}/ipmi.yml \
          -path ${pkgs.freeipmi}/bin/
      '';
    };
  };

  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1:9090";
    exporters = {
      unifi = {
        enable = true;
        unifiAddress = "https://unifi.lan:8443";
        unifiInsecure = true;
        unifiUsername = "readonly";
        unifiPassword = "readonly";
      };
      snmp = {
        enable = true;
        configuration = null;
        configurationPath = "${pkgs.prometheus-snmp-exporter.src}/snmp.yml";
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
        relabel_configs = [
          {
            source_labels = ["__meta_consul_service"];
            regex = "(.*)";
            target_label = "job";
            replacement = "$1";
          }
          {
            source_labels = ["__meta_consul_node"];
            regex = "(.*)";
            target_label = "instance";
            replacement = "$1";
          }
        ];
      }
      {
        job_name = "nginx";
        static_configs = [{
          targets = [ "127.0.0.1:9113" ];
          labels = {};
        }];
      }
      {
        job_name = "unifi";
        static_configs = [{
          targets = [ "127.0.0.1:9130" ];
          labels = {};
        }];
      }
      {
        job_name = "prometheus";
        static_configs = [{
          targets = [ "127.0.0.1:9090" ];
          labels = {};
        }];
      }
      {
        job_name = "ipmi";
        static_configs = [{
          targets = [ "127.0.0.1:9290" ];
          labels = {};
        }];
      }
      {
        job_name = "snmp";
        metrics_path = "/snmp";
        params = { module = [ "if_mib" ]; };
        relabel_configs = [
          { source_labels = ["__address__"];    target_label = "__param_target"; }
          { source_labels = ["__param_target"]; target_label = "instance"; }
          { source_labels = []; target_label = "__address__"; replacement = "localhost:9116"; }
        ];
        static_configs = [{
          targets = [ "mikrotik.lan" ];
        }];
      }

    ];
  };

}
