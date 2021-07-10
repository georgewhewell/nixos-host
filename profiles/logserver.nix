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

  /* services.loki = let
    configFile = pkgs.writeText "loki-config.yaml" ''
      ingester:
        lifecycler:
          interface_names: ["br0"]

      schema_config:
        configs:
          - from: 2020-10-24
            store: boltdb-shipper
            object_store: filesystem
            schema: v11
            index:
              prefix: index_
              period: 24h

      storage_config:
        boltdb_shipper:
          active_index_directory: /tmp/loki/boltdb-shipper-active
          cache_location: /tmp/loki/boltdb-shipper-cache
          cache_ttl: 24h         # Can be increased for faster performance over longer query periods, uses more disk space
          shared_store: filesystem
        filesystem:
          directory: /tmp/loki/chunks
    '';
  in {
    enable = true;
    inherit configFile;
  }; */

  services.prometheus = {
    enable = true;
    listenAddress = "0.0.0.0";
    /* port = 9090; */
    exporters = {
      unifi = {
        enable = true;
        unifiAddress = "https://unifi.lan:8443";
        unifiInsecure = true;
        unifiUsername = "readonly";
        unifiPassword = "&)l_Q4s?f}ai5}k=Q(z=ph;C3";
      };
      snmp = {
        enable = true;
        configuration = null;
        configurationPath = "${pkgs.prometheus-snmp-exporter.src}/snmp.yml";
      };
    };
    scrapeConfigs = [
      {
        job_name = "node";
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
            source_labels = [ ];
            regex = "(.*)";
            target_label = "port";
            replacement = "9100";
          }
          {
            source_labels = [ "__meta_consul_node" ];
            regex = "(.*)";
            target_label = "instance";
            replacement = "$1:9100";
          }
        ];
      }
      {
        job_name = "nginx";
        static_configs = [{
          targets = [ "127.0.0.1:9113" ];
          labels = { };
        }];
      }
      {
        job_name = "unifi";
        static_configs = [{
          targets = [ "127.0.0.1:9130" ];
          labels = { };
        }];
      }
      {
        job_name = "prometheus";
        static_configs = [{
          targets = [ "127.0.0.1:9090" ];
          labels = { };
        }];
      }
      {
        job_name = "ipmi";
        static_configs = [{
          targets = [ "127.0.0.1:9290" ];
          labels = { };
        }];
      }
      {
        job_name = "snmp";
        metrics_path = "/snmp";
        params = { module = [ "if_mib" ]; };
        relabel_configs = [
          { source_labels = [ "__address__" ]; target_label = "__param_target"; }
          { source_labels = [ "__param_target" ]; target_label = "instance"; }
          { source_labels = [ ]; target_label = "__address__"; replacement = "localhost:9116"; }
        ];
        static_configs = [{
          targets = [ "mikrotik.lan" ];
        }];
      }

    ];
  };

}
