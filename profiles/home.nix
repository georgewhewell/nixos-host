{ config, pkgs, lib, ... }:

{
  # Config for machines on home network
  time.timeZone = "Europe/Zurich";

  nix.settings = {
    binary-caches = [
      https://cache.nixos.org
    ];
    trusted-public-keys = [
      "hydra.satanic.link-1:dqovbpJdboPkY2O2D4UAh4IgEReKf608IJ7aLl6CAoM="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nixos-arm.dezgeg.me-1:xBaUKS3n17BZPKeyxL4JfbTqECsT+ysbDJz29kLFRW0=%"
    ];
  };

  # Collect metrics for prometheus
  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = false;
      enabledCollectors = [ "systemd" ];
    };
  };

  services.cadvisor = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 58080;
  };

  networking.firewall.allowedTCPPorts = [ 58080 ];
  networking.nameservers = [ "192.168.23.1" ];
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="powercap", MODE="0666"
  '';

}
