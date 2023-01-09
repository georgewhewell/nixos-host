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

  # networking.firewall.allowedTCPPorts = [ 8500 8300 8301 8302 8300 8602 8600 ];
  # networking.firewall.allowedUDPPorts = [ 8500 8301 8302 8300 8602 8600 ];

  # Collect metrics for prometheus
  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = false;
      enabledCollectors = [ "systemd" ];
    };
  };

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="powercap", MODE="0666"
  '';

}
