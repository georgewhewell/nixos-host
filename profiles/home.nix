{ config, pkgs, ... }:

{
  # Config for machines on home network
  time.timeZone = "Europe/London";

  nix.binaryCaches = [
      https://hydra.satanic.link
      https://cache.satanic.link
      https://cache.nixos.org
  ];
  nix.binaryCachePublicKeys = [
    "hydra.satanic.link-1:U4ZvldOwA3GWLmFTqdXwUu9oS0Qzh4+H/HSl8O6ew5o="
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nixos-arm.dezgeg.me-1:xBaUKS3n17BZPKeyxL4JfbTqECsT+ysbDJz29kLFRW0=%"
  ];
/*
  services.consul = {
    enable = true;
    leaveOnStop = true;
    forceIpv4 = true;
    extraConfig = {
      retry_join = [ "nixhost.lan" "router.lan" ];
    };
  };

  systemd.services.register-consul-node-exporter = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "consul.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "true";
      ExecStartPre="${pkgs.bash}/bin/bash -c 'sleep 1'";
      ExecStart = ''
        ${pkgs.consul}/bin/consul services register -name node_exporter -port 9100
      '';
    };
  }; */

  networking.firewall.allowedTCPPorts = [ 8500 8301 8302 8300 ];
  networking.firewall.allowedUDPPorts = [ 8500 8301 ];

  # Log to ELK
  services.journalbeat = {
    enable = false;
    extraConfig = ''
      journalbeat:
        seek_position: cursor
        cursor_seek_fallback: tail
        write_cursor_state: true
        cursor_flush_period: 5s
        clean_field_names: true
        convert_to_numbers: false
        move_metadata_to_field: journal
        default_type: journal

      setup.kibana:
        host: "localhost:5601"

      output.elasticsearch:
        enabled: true
        protocol: "https"
        hosts: [ "es.satanic.link:443" ]
        index: "controllers"
        template.enabled: false

      queue_size: 50000
      logging.level: error
      logging.to_files: false
    '';
  };

  # Collect metrics for prometheus
  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = true;
      enabledCollectors = [ "systemd" ];
    };
  };

}
