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
  networking.nameservers = [network.dnsIp];
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
    port = 9188;
  };

  networking.firewall.allowedTCPPorts = lib.mkIf enableCadvisor [
    config.services.cadvisor.port
  ];

  # systemd-networkd enables systemd-resolved by default. Let resolved handle
  # ordinary per-link mDNS, but leave it disabled on the router where Avahi is
  # explicitly enabled to reflect HomeKit discovery between LAN and WiFi.
  services.resolved.settings.Resolve.MulticastDNS =
    if config.services.avahi.enable then "no" else "yes";
}
