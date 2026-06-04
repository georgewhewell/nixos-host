{
  config,
  pkgs,
  lib,
  mkSecret,
  network,
  ...
}: let
  apcIp = network.primaryIp network.hosts."apc-ups";
  trexIp = network.primaryIp network.hosts.trex;
  ipmiExporterConfig = pkgs.writeText "ipmi-local-fast.yml" ''
    modules:
      default:
        collectors:
          - bmc
          - ipmi
          - dcmi
          - chassis
        exclude_sensor_ids:
          - 2
          - 29
          - 32
  '';
in {
  sops.secrets.nut-upsmon = mkSecret "nut-upsmon" {};
  sops.secrets.hass-prometheus-token = mkSecret "hass-prometheus-token" {};
  environment.systemPackages = with pkgs; [
    ipmitool
    lm_sensors
  ];

  boot.kernelModules = ["ipmi_si" "ipmi_devintf" "ipmi_msghandler"];

  # APC UPS monitoring via network management card
  services.apcupsd = {
    enable = true;
    configText = ''
      UPSCABLE ether
      UPSTYPE snmp
      DEVICE ${apcIp}
      POLLTIME 60
      NISIP ${trexIp}
      NISPORT 3551
    '';
  };

  services.prometheus.exporters.apcupsd = {
    enable = true;
    listenAddress = "127.0.0.1";
    apcupsdAddress = "${trexIp}:3551";
  };

  # NUT prometheus exporter
  systemd.services.prometheus-nut-exporter = {
    description = "Prometheus NUT Exporter";
    wantedBy = ["multi-user.target"];
    after = ["upsd.service"];
    serviceConfig = {
      ExecStart = ''${pkgs.prometheus-nut-exporter}/bin/nut_exporter --nut.server=127.0.0.1 --web.listen-address=127.0.0.1:9199 --nut.vars_enable=""'';
      Restart = "always";
      DynamicUser = true;
    };
  };

  # Ensure UPS services wait for network to be online
  systemd.services.apcupsd = {
    wants = ["network-online.target"];
    after = ["network-online.target"];
  };
  systemd.services.upsd = {
    wants = ["network-online.target"];
    after = ["network-online.target"];
  };
  systemd.services.upsdrv = {
    wants = ["network-online.target"];
    after = ["network-online.target"];
  };

  # NUT for UPS monitoring and control
  power.ups = {
    enable = true;
    mode = "netserver";
    upsd.listen = [
      {address = "127.0.0.1";}
      {address = trexIp;}
    ];
    ups.apc = {
      driver = "snmp-ups";
      port = apcIp;
      description = "APC Smart-UPS 3000";
      directives = [
        "community = public"
        "snmp_version = v2c"
        "pollfreq = 10"
      ];
    };
    users.upsmon = {
      upsmon = "primary";
      passwordFile = "/run/secrets/nut-upsmon";
    };
    upsmon.monitor.apc = {
      user = "upsmon";
      system = "apc@localhost";
      powerValue = 1;
    };
    upsmon.settings = {
      # Don't shutdown - no battery installed
      SHUTDOWNCMD = "/run/current-system/sw/bin/true";
      # Require 0% battery before considering shutdown (never triggers without battery)
      MINSUPPLIES = 0;
    };
  };

  systemd.services.prometheus-ipmi-exporter = {
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    serviceConfig = {
      ExecStart = ''
        ${pkgs.prometheus-ipmi-exporter}/bin/ipmi_exporter \
          --config.file ${ipmiExporterConfig} \
          --freeipmi.path ${pkgs.freeipmi}/bin/
      '';
    };
  };

  sconfig.gcp-ddns = let
    domain = network.publicFqdn "grafana";
  in {
    aRecords = [domain];
    aaaaRecords = [domain];
  };

  services.nginx.virtualHosts.${network.publicFqdn "grafana"} = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3005";
      proxyWebsockets = true;
    };
  };

  services.prometheus.exporters = {
    snmp = {
      enable = true;
      enableConfigCheck = false;
      configuration = null;
      configurationPath = "${pkgs.prometheus-snmp-exporter.src}/snmp.yml";
    };
    postgres = {
      enable = true;
      user = "postgres";
      extraFlags = ["--auto-discover-databases"];
    };
    dnsmasq = {
      enable = true;
    };
    smartctl = {
      enable = true;
    };
  };
}
