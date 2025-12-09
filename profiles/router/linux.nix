{lib, ...}: let
  wanInterface = "enp1s0f0np0";
  lanBridge = "br0.lan";
in {
  services.usbmuxd.enable = true;
  services.avahi.allowInterfaces = lib.mkForce [lanBridge];

  services.miniupnpd = {
    enable = true;
    externalInterface = wanInterface;
    internalIPs = [lanBridge];
    natpmp = true;
    upnp = true;
  };

  # make miniupnpd wait for network to be online
  systemd.services.miniupnpd = {
    after = ["network-online.target"];
    wants = ["network-online.target"];
  };

  boot.kernel.sysctl = {
    "net.core.rmem_default" = 1048576;
    "net.core.wmem_default" = 1048576;
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.core.netdev_max_backlog" = 50000;
    "net.core.netdev_budget" = 1000;
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.ipv4.route.max_size" = 524288;
    "net.ipv4.tcp_fastopen" = "3";
    "net.ipv6.conf.all.forwarding" = true;
    "net.netfilter.nf_conntrack_max" = 131072;
    "net.nf_conntrack_max" = 131072;
  };

  systemd.network = {
    wait-online.enable = true;
    netdevs = {
      "20-${lanBridge}" = {
        netdevConfig = {
          Kind = "bridge";
          Name = lanBridge;
        };
      };
    };
    links = {
      "20-${wanInterface}" = {
        matchConfig = {
          Driver = "mlx5_core";
          Path = "pci-0000:01:00.0";
        };
        linkConfig = {
          RxBufferSize = 8192;
          TxBufferSize = 8192;
        };
      };
    };
    networks = {
      "10-${lanBridge}" = {
        matchConfig.Name = lanBridge;
        bridgeConfig = {};
        address = [
          "192.168.23.1/24"
          "fdde:ad::1/64"  # ULA for LAN
        ];
        networkConfig = {
          ConfigureWithoutCarrier = true;
          DHCPPrefixDelegation = true;
          IPv6AcceptRA = false;
          IPv6SendRA = true;
          IPv6Forwarding = true;
        };
        dhcpPrefixDelegationConfig = {
          Announce = true;
        };
        ipv6SendRAConfig = {
          # RouterLifetimeSec = 300;
          Managed = false;
          # Only RA (no DHCPv6 for DNS); advertise DNS via RDNSS
          EmitDNS = true;
          DNS = ["fdde:ad::1"];
          Domains = "lan.satanic.link";
        };
        linkConfig.RequiredFamilyForOnline = "ipv4";
      };
      "20-thunderbolt" = {
        matchConfig.Driver = "thunderbolt-net";
        networkConfig.Bridge = lanBridge;
        linkConfig.RequiredForOnline = "no";
      };
      "20-lan-25g" = {
        matchConfig.Name = "enp1s0f1np1";
        networkConfig.Bridge = lanBridge;
        linkConfig.RequiredForOnline = "enslaved";
      };

      "20-lan-10g" = {
        matchConfig.Driver = "atlantic";
        networkConfig.Bridge = lanBridge;
        linkConfig.RequiredForOnline = "no";
      };
      "20-lan-2-5g" = {
        matchConfig.Driver = "igc";
        networkConfig.Bridge = lanBridge;
        linkConfig.RequiredForOnline = "no";
      };
      "20-thunderbolt-mlx5-0" = {
        matchConfig = {
          Driver = "mlx5_core";
          Path = "pci-0000:0b:*";
        };
        networkConfig.Bridge = lanBridge;
        linkConfig.RequiredForOnline = "no";
      };
      "20-thunderbolt-mlx5-1" = {
        matchConfig = {
          Driver = "mlx5_core";
          Path = "pci-0000:0c:*";
        };
        networkConfig.Bridge = lanBridge;
        linkConfig.RequiredForOnline = "no";
      };
      "20-${wanInterface}" = {
        matchConfig.Name = wanInterface;
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
          IPv6PrivacyExtensions = false;
          IPv6Forwarding = true;
          IgnoreCarrierLoss = true;
        };
        dhcpV4Config = {
          UseDNS = false;
          UseDomains = false;
          SendRelease = false;
        };
        dhcpV6Config = {
          WithoutRA = "solicit";
          PrefixDelegationHint = "::/56";
        };
        ipv6SendRAConfig.Managed = true;
        linkConfig.RequiredFamilyForOnline = "both";
      };
    };
  };

  networking = {
    useDHCP = false;

    enableIPv6 = true;
    useNetworkd = true;
    nftables.enable = true;

    domain = "lan.satanic.link";
    nameservers = ["192.168.23.1"];

    nat = {
      enable = true;
      internalIPs = [
        "192.168.23.0/24"
      ];
      internalInterfaces = [
        lanBridge
      ];
      externalInterface = wanInterface;
      forwardPorts = [
        {
          sourcePort = 80;
          destination = "192.168.23.8:80";
          proto = "tcp";
        } # nginx
        {
          sourcePort = 443;
          destination = "192.168.23.8:443";
          proto = "tcp";
        } # nginx
        {
          sourcePort = 17026;
          destination = "192.168.23.8:17026";
          proto = "tcp";
        } # qBittorrent
        {
          sourcePort = 17026;
          destination = "192.168.23.8:17026";
          proto = "udp";
        } # qBittorrent
        {
          sourcePort = 9000;
          destination = "192.168.23.8:9000";
          proto = "tcp";
        } # Lighthouse
        {
          sourcePort = 9000;
          destination = "192.168.23.8:9000";
          proto = "udp";
        } # Lighthouse
        {
          sourcePort = 9001;
          destination = "192.168.23.8:9001";
          proto = "udp";
        } # Lighthouse
        {
          sourcePort = 18080;
          destination = "192.168.23.8:18080";
          proto = "tcp";
        } # Monero
        {
          sourcePort = 18080;
          destination = "192.168.23.8:18080";
          proto = "udp";
        } # Monero
        {
          sourcePort = 30303;
          destination = "192.168.23.8:30303";
          proto = "tcp";
        } # Reth (Ethereum)
        {
          sourcePort = 30303;
          destination = "192.168.23.8:30303";
          proto = "udp";
        } # Reth (Ethereum)
        {
          sourcePort = 8333;
          destination = "192.168.23.8:8333";
          proto = "tcp";
        } # Bitcoin
        {
          sourcePort = 8333;
          destination = "192.168.23.8:8333";
          proto = "udp";
        } # Bitcoin
        {
          sourcePort = 51412;
          destination = "192.168.23.8:51412";
          proto = "udp";
        } # rtorrent
        {
          sourcePort = 51412;
          destination = "192.168.23.8:51412";
          proto = "tcp";
        } # rtorrent
      ];
    };

    firewall = {
      enable = true;
      checkReversePath = false;
      trustedInterfaces = [lanBridge "wg-home"];
      logRefusedConnections = false;
      logRefusedPackets = false;
      logReversePathDrops = false;
      interfaces = {
        "${wanInterface}" = {
          allowedTCPPorts = [
            22 # ssh
            80 # http
            443 # https
            51413 # transmission
            32400 # plex
            3074 # bo2

            9000 # lighthouse
            9001 # lighthouse
            9002 # lighthouse

            30303 # geth
            30304 # reth

            18080 # monero
            17026 # qBittorrent
            37889 # P2Pool P2P
            42069 # Snap sync (Bittorrent)
          ];
          allowedUDPPorts = [
            546 # dhcpv6 (client)
            547 # dhcpv6 (server)
            35947 # wireguard
            51820 # wireguard (cloud)
            51821 # wireguard (swaps)
            51413 # transmission
            17026 # qBittorrent
            3074 # bo2
            3478 # bo2

            5000 # (IPTV)

            9000 # lighthouse
            9001 # lighthouse
            9002 # lighthouse

            30303 # geth
            30304 # reth

            18080 # monero
            37889 # P2Pool P2P

            42069 # Snap sync (Bittorrent)

            60001 # mosh
          ];
        };
      };
    };
  };
}
