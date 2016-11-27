{ config, lib, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    lm_sensors
  ];

  services.prometheus = {
      enable = true;
      nodeExporter = {
        enable = true;
        enabledCollectors = [
          "systemd"
        ];
      };
      scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [{
          targets = [ "127.0.0.1:9090" ];
          labels = { instance = "nixhost"; };
        }];
      }
      {
        job_name = "nixhost-node";
        static_configs = [{
          targets = [ "127.0.0.1:9100" ];
          labels = { instance = "nixhost"; };
        }];
      }
      {
        job_name = "snmp";
        metrics_path = "/snmp";
        relabel_configs = [
          {source_labels = ["__address__"]; target_label = "__param_target";}
          {source_labels = ["__param_target"]; target_label = "instance";}
          {source_labels = []; target_label = "__address__"; replacement = "127.0.0.1:9116";}
        ];
        static_configs = [{
          targets = [
            "192.168.23.1" # firewall
            "192.168.23.2" # switch
            "192.168.23.3" # unifi 
          ];
          labels = { instance = "nixhost"; };
        }];
      }
      ];
  };

  networking.firewall.allowedTCPPorts = [ 9090 9100 9116 ];

  systemd.services.snmp_exporter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --rm \
        --net="host" \
        quay.io/prometheus/snmp-exporter'';
    };
  };

}
