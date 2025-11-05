{
  config,
  pkgs,
  ...
}: {
  # Config for machines on home network
  time.timeZone = "Europe/Zurich";
  location = {
    latitude = 51.5;
    longitude = 0.0;
  };

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="powercap", MODE="0666"
    ACTION=="add", SUBSYSTEM=="nvme", KERNEL=="nvme[0-9]*", RUN+="${pkgs.acl}/bin/setfacl -m g:smartctl-exporter-access:rw /dev/$kernel"
    ACTION=="add"  SUBSYSTEM=="block", KERNEL=="sd[a-z]*", RUN+="${pkgs.acl}/bin/setfacl -m g:smartctl-exporter-access:rw /dev/$kernel"
  '';

  # Collect metrics for prometheus
  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = true;
      enabledCollectors = ["systemd"];
    };
    zfs = {
      enable = true;
      openFirewall = true;
    };
    smartctl = {
      enable = true;
      openFirewall = true;
    };
  };

  services.cadvisor = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 58080;
  };

  networking.firewall.allowedTCPPorts = [
    config.services.cadvisor.port
  ];

  networking.nameservers = ["192.168.23.1"];
}
