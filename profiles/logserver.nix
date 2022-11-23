{ config, pkgs, ... }:

{

  environment.systemPackages = with pkgs; [
    ipmitool
    lm_sensors
  ];

  boot.kernelModules = [ "ipmi_si" "ipmi_devintf" "ipmi_msghandler" ];
  # networking.firewall.allowedTCPPorts = [ 9090 ];

  systemd.services.prometheus-ipmi-exporter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = ''
        ${pkgs.prometheus-ipmi-exporter}/bin/ipmi_exporter \
          -config.file ${pkgs.prometheus-ipmi-exporter.src}/ipmi.yml \
          -path ${pkgs.freeipmi}/bin/
      '';
    };
  };

  services.prometheus = {
    enable = true;
    listenAddress = "0.0.0.0";
    exporters = {
      snmp = {
        enable = true;
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
            "ax101.lan:9100"
          ];
        }];
      }
      {
        job_name = "nginx";
        static_configs = [{
          targets = [ "127.0.0.1:9113" "ax101.lan:9113" ];
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
          targets = [ "127.0.0.1:9187" "ax101.lan:9187" ];
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
          targets = [ "router.lan:9153" ];
        }];
      }

      {
        job_name = "geth_node";
        metrics_path = "/debug/metrics/prometheus";
        static_configs = [{
          targets = [ "ax101.lan:6060" "ax101.lan:6061" ];
        }];
      }
      {
        job_name = "nft_bot";
        static_configs = [{
          targets = [ "ax101.lan:9099" ];
        }];
      }
      {
        job_name = "arb_bot";
        static_configs = [{
          targets = [ "ax101.lan:9199" ];
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
