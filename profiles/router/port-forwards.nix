# Shared port forward definitions for router
# Used by both Linux NAT (linux.nix) and VPP NAT (vpp.nix)
#
# Each forward has:
#   - port: external port number
#   - dstPort: internal port (optional, defaults to port)
#   - proto: "tcp", "udp", or "both"
#   - comment: description
#
# Special entry "router" is for LAN hairpin NAT (.1 -> .254)
network: {
  # Router local services
  router = {
    ip = network.routerIp;
    forwards = [
      {
        port = 53;
        proto = "both";
        comment = "DNS (dnsmasq)";
      }
      # { port = 8123; proto = "tcp"; comment = "Home Assistant"; }
      # { port = 1883; proto = "tcp"; comment = "MQTT (mosquitto)"; }
      # { port = 6052; proto = "tcp"; comment = "ESPHome"; }
      # { port = 8009; proto = "tcp"; comment = "Frigate/nginx"; }
      # { port = 9050; proto = "tcp"; comment = "Tor SOCKS"; }
      # # Unifi
      # { port = 8443; proto = "tcp"; comment = "Unifi Web UI"; }
      # { port = 8080; proto = "tcp"; comment = "Unifi device comm"; }
      # { port = 8843; proto = "tcp"; comment = "Unifi HTTPS redirect"; }
      # { port = 8880; proto = "tcp"; comment = "Unifi HTTP portal"; }
      # { port = 6789; proto = "tcp"; comment = "Unifi speed test"; }
      # { port = 3478; proto = "udp"; comment = "Unifi STUN"; }
      # { port = 10001; proto = "udp"; comment = "Unifi discovery"; }
      # { port = 5514; proto = "udp"; comment = "Unifi syslog"; }
    ];
  };

  # Media services live in the arr-servers container on trex, with their own
  # VF and their own address (2026-08-09). qBittorrent's listen port must be
  # forwarded there, not to trex -- otherwise inbound peer connections just
  # stop arriving, silently, and the only symptom is a worse swarm.
  arr-servers = {
    ip = network.ipOf "lan" network.hosts."arr-servers".addresses.lan;
    forwards = [
      {
        port = 17026;
        proto = "both";
        comment = "qBittorrent";
      }
    ];
  };

  # router external access
  router-wan = {
    ip = network.routerIp;
    forwards = [
      {
        port = 22;
        proto = "tcp";
        comment = "SSH";
      }
      {
        port = 9999;
        proto = "tcp";
        comment = "Tor ORPort";
      }
    ];
  };

  # The Linux router becomes an ordinary control-plane host during the VPP
  # handoff. Preserve the home WireGuard endpoint without restoring direct
  # WAN SSH or the old Tor relay publication.
  router-control = {
    ip = network.controlPlaneIp;
    forwards = [
      {
        port = 51820;
        proto = "udp";
        comment = "Home WireGuard on the retired Linux router";
      }
    ];
  };

  # trex
  trex = {
    ip = network.primaryIp network.hosts.trex;
    ipv6 = {
      # mlxlan0 uses stable SLAAC/EUI-64. The delegated prefix is deliberately
      # absent here: VPP learns it at runtime and composes the exact /128.
      interfaceMac = builtins.head network.hosts.trex.extraMacs;
      subnetId = network.routing.production.transition.legacyInside.delegatedSubnetId;
    };
    forwards = [
      {
        port = 80;
        proto = "tcp";
        comment = "nginx";
        publishIpv6 = true;
      }
      {
        port = 443;
        proto = "tcp";
        comment = "nginx";
        publishIpv6 = true;
      }
      {
        port = 18080;
        proto = "both";
        comment = "Monero";
      }
      {
        port = 8333;
        proto = "both";
        comment = "Bitcoin";
      }
      {
        port = 18141;
        proto = "both";
        comment = "Tari P2P";
      }
      {
        port = 3333;
        proto = "tcp";
        comment = "P2Pool stratum";
      }
      {
        port = 37899;
        dstPort = 37889;
        proto = "both";
        comment = "P2Pool (C++)";
      }
    ];
  };
}
