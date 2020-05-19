{ config, pkgs, lib, ... }:

{
  # Config for machines on home network
  time.timeZone = "Europe/London";

  nix.binaryCaches = [
#      https://hydra.satanic.link
#      https://cache.satanic.link
      https://cache.nixos.org
  ];
  nix.binaryCachePublicKeys = [
    "hydra.satanic.link-1:U4ZvldOwA3GWLmFTqdXwUu9oS0Qzh4+H/HSl8O6ew5o="
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nixos-arm.dezgeg.me-1:xBaUKS3n17BZPKeyxL4JfbTqECsT+ysbDJz29kLFRW0=%"
  ];

  services.consul = {
    enable = true;
    leaveOnStop = true;
    forceIpv4 = true;
    interface.bind = lib.mkDefault "eth0";
    extraConfig = {
      retry_join = [ "nixhost" ];
    };
  };

  systemd.services.register-consul-node-exporter = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "consul.service" ];
    serviceConfig = {
      RemainAfterExit = "true";
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStart = ''
        ${pkgs.consul}/bin/consul services register -name node -port 9100
      '';
    };
  };

  networking.firewall.allowedTCPPorts = [ 8500 8301 8302 8300 8602 8600 ];
  networking.firewall.allowedUDPPorts = [ 8500 8301 8302 8300 8602 8600 ];

  # Collect metrics for prometheus
  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = true;
      enabledCollectors = [ "systemd" ];
    };
  };

}
