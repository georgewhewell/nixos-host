{
  config,
  pkgs,
  lib,
  ...
}: {
  # Config for machines on home network
  networking.nameservers = ["192.168.23.1"];

  time.timeZone = "Europe/Zurich";

  location = {
    latitude = 51.5;
    longitude = 0.0;
  };

  # Collect metrics for prometheus
  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = true;
      enabledCollectors = ["systemd"];
    };
    # only on x86_64 servers with disks
    zfs = {
      enable = config.boot.kernelPackages.stdenv.isx86_64 && lib.hasAttr "zfs" config.boot.kernelPackages;
      openFirewall = true;
    };
    smartctl = {
      enable = config.boot.kernelPackages.stdenv.isx86_64;
      openFirewall = true;
    };
  };

  services.cadvisor = {
    enable = config.boot.kernelPackages.stdenv.isx86_64;
    listenAddress = "0.0.0.0";
    port = 58080;
  };

  networking.firewall.allowedTCPPorts = [
    config.services.cadvisor.port
  ];

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      userServices = true;
    };
  };
}
