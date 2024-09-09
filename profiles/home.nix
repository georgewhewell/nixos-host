{ config, pkgs, lib, ... }:

{
  # Config for machines on home network
  time.timeZone = "Europe/Zurich";

  nix.settings = {
    binary-caches = [
      https://cache.nixos.org
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
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
