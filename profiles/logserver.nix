{ config, pkgs, ... }:

{

  environment.systemPackages = with pkgs; [
    ipmitool
    lm_sensors
  ];

  boot.kernelModules = [ "ipmi_si" "ipmi_devintf" "ipmi_msghandler" ];

  systemd.services.prometheus-ipmi-exporter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = ''
        ${pkgs.prometheus-ipmi-exporter}/bin/ipmi_exporter \
          --config.file ${pkgs.prometheus-ipmi-exporter.src}/ipmi_local.yml \
          --freeipmi.path ${pkgs.freeipmi}/bin/
      '';
    };
  };

  services.prometheus = {
    enable = true;
    listenAddress = "0.0.0.0";
    exporters = {
      snmp = {
        enable = false;
        configuration = null;
        configurationPath = "${pkgs.prometheus-snmp-exporter.src}/snmp.yml";
      };
      postgres = {
        enable = true;
        extraFlags = [ "--auto-discover-databases" ];
      };
      dnsmasq = {
        enable = true;
      };
      smartctl = {
        enable = true;
      };
    };

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{
          targets = [
            "nixhost.lan:9100"
            "fuckup.lan:9100"
            "router.lan:9100"
            "trex.lan:9100"
            "rock-5b.lan:9100"
            "air.lan:9100"
          ];
        }];
      }
      {
        job_name = "cadvisor";
        static_configs = [{
          targets = [
            "nixhost.lan:58080"
            "fuckup.lan:58080"
            "router.lan:58080"
            "trex.lan:58080"
            "rock-5b.lan:58080"
          ];
        }];
      }
      {
        job_name = "nginx";
        static_configs = [{
          targets = [
            "127.0.0.1:9113"
          ];
        }];
      }
      {
        job_name = "unifi";
        static_configs = [{
          targets = [ "127.0.0.1:9130" ];
        }];
      }
      {
        job_name = "prometheus";
        static_configs = [{
          targets = [ "127.0.0.1:9090" ];
        }];
      }
      {
        job_name = "postgres";
        static_configs = [{
          targets = [ "127.0.0.1:9187" ];
        }];
      }
      {
        job_name = "ipmi";
        static_configs = [{
          targets = [ "127.0.0.1:9290" ];
        }];
      }
      {
        job_name = "dnsmasq";
        static_configs = [{
          targets = [ "127.0.0.1:9153" ];
        }];
      }
      {
        job_name = "smart";
        static_configs = [{
          targets = [ "127.0.0.1:9633" ];
        }];
      }

      {
        job_name = "geth_node";
        metrics_path = "/debug/metrics/prometheus";
        static_configs = [{
          targets = [ "127.0.0.1:6060" ];
        }];
      }

      {
        job_name = "lighthouse";
        static_configs = [{
          targets = [ "127.0.0.1:5054" "127.0.0.1:5055" ];
        }];
      }
      {
        job_name = "reth";
        static_configs = [{
          targets = [ "127.0.0.1:9009" ];
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
