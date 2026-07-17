{...}: {
  # Reflect mDNS between the wired LAN and the WiFi VLAN so HomeKit
  # controllers (iPhone/HomePods on VLAN 50) can discover the bridge,
  # which HA only announces on br0.lan.
  # (allowed interfaces are set in profiles/router/linux.nix)
  services.avahi = {
    enable = true;
    reflector = true;
  };

  # LAN-only: these were previously open on all interfaces, exposing the
  # HomeKit bridge (and mDNS) to the internet on the WAN interface.
  networking.firewall.interfaces."br0.lan" = {
    allowedUDPPorts = [5353];
    allowedTCPPorts = [21063];
  };
  networking.firewall.interfaces."br0.lan.50" = {
    allowedUDPPorts = [5353];
    allowedTCPPorts = [21063];
  };

  services.home-assistant.config.zeroconf = {};
  services.home-assistant.config.homekit = {
    filter = {
      include_domains = ["light"];
    };
  };

  services.home-assistant.config.logger = {
    default = "info";
  };
}
