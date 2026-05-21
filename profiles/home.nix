{
  config,
  pkgs,
  lib,
  network,
  ...
}: let
  hasContainerRuntime =
    config.virtualisation.docker.enable
    || config.virtualisation.podman.enable
    || config.virtualisation.oci-containers.containers != {};
  enableCadvisor = pkgs.stdenv.hostPlatform.isx86_64 && hasContainerRuntime;
in {
  # Config for machines on home network
  networking.nameservers = [network.routerIp];
  networking.search = lib.mkDefault [network.domains.lan];

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
      enable = pkgs.stdenv.hostPlatform.isx86_64 && lib.hasAttr "zfs" config.boot.kernelPackages;
      openFirewall = true;
    };
    smartctl = {
      enable = pkgs.stdenv.hostPlatform.isx86_64;
      openFirewall = true;
    };
  };

  services.cadvisor = {
    enable = enableCadvisor;
    listenAddress = "0.0.0.0";
    port = 58080;
  };

  networking.firewall.allowedTCPPorts = lib.mkIf enableCadvisor [
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

  services.resolved.settings.Resolve.MulticastDNS = "no";
}
