{network, driver ? "rdma", hostPfMode ? "off"}: let
  platform = import ./vpp-platform.nix {inherit network driver hostPfMode;};
in
  platform
  // {
  baseAddresses = [
    (network.cidrOf "fabric" network.hosts.bluefield2.addresses.fabric)
    "198.18.0.1/24"
    "198.18.1.1/24"
  ];

  backupWan = {
    subId = network.vlans.wanBackup.id;
    mtu = network.vlans.wanBackup.mtu;
    ipv4 = {
      prefix = network.vlans.wanBackup.prefix;
      cidr = network.vlans.wanBackup.cidr;
      localHost = network.hosts.bluefield2.addresses.wanBackup;
      peerHost = network.hosts.k3.addresses.wanBackup;
    };
    # Keep the untagged bootstrap available as recovery even after VLAN 101 is
    # admitted on k3's CRS812 downlink.
    # Keep the proper tagged transit staged, but bootstrap the two test routes
    # over the existing flat L2 until its cable moves onto the CRS fabric.
    bootstrap = {
      enable = true;
      interface = platform.dataName;
      localAddress = network.cidrOf "lan" network.hosts."bluefield2-vpp-lan".addresses.lan;
      peerAddress = network.primaryIp network.hosts.k3;
    };
    # Keep route injection gated separately from bringing up the transit VLAN.
    # These host routes prove failover without stealing VPP's lab WAN.
    installTestRoutes = true;
    testRoutes = [
      "1.1.1.1/32"
      "9.9.9.9/32"
    ];
  };

  # The order is significant only for readable, deterministic generated CLI.
  zoneOrder = [
    "trusted"
    "wan"
    "restricted"
  ];
  zones = {
    trusted = {
      subId = 3901;
      mtu = network.vlans.fabric.mtu;
      qosClass = "bestEffort";
      ipv4 = {
        prefix = "198.18.10";
        cidr = 24;
        localHost = 1;
        peerHost = 2;
      };
      ipv6 = {
        prefix = "2001:db8:10";
        cidr = 64;
        localHost = 1;
        peerHost = 2;
      };
    };
    wan = {
      subId = 3902;
      mtu = 1500;
      qosClass = "bestEffort";
      ipv4 = {
        prefix = "203.0.113";
        cidr = 24;
        localHost = 2;
        peerHost = 100;
      };
      ipv6 = {
        prefix = "2001:db8:ffff";
        cidr = 64;
        localHost = 1;
        peerHost = 100;
      };
    };
    restricted = {
      subId = 3903;
      mtu = network.vlans.fabric.mtu;
      qosClass = "bulk";
      ipv4 = {
        prefix = "198.18.20";
        cidr = 24;
        localHost = 1;
        peerHost = 2;
      };
      ipv6 = {
        prefix = "2001:db8:20";
        cidr = 64;
        localHost = 1;
        peerHost = 2;
      };
    };
  };

  qosClasses = {
    bestEffort.dscp = 0;
    bulk.dscp = 8;
    streaming.dscp = 34;
    interactive.dscp = 46;
    control.dscp = 56;
  };

  services = {
    qbittorrent = {
      port = 17026;
      protocols = [
        "tcp"
        "udp"
      ];
      targetZone = "trusted";
    };
    restrictedTest = {
      port = 5201;
      protocol = 6;
      sourceZone = "restricted";
      targetZone = "wan";
    };
  };

  nat44 = {
    insideZones = [
      "trusted"
      "restricted"
    ];
    outsideZone = "wan";
    sessions = 131072;
    frameQueueLength = 256;
  };

  # VPP assigns ACL indices in creation order.  Consumers derive the numeric
  # indices from this list; none are repeated by hand in the renderer.
  aclOrder = [
    "restricted"
    "trusted"
    "wan"
    "wanEgressState"
  ];
}
