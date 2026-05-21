{lib, pkgs, network, ...}: let
  wanInterface = "enp1s0f0np0";
  lanBridge = "br0.lan";
  lanCidr = "${network.vlans.lan.prefix}.0/${toString network.vlans.lan.cidr}";

  # Import shared port forward definitions
  portForwardHosts = import ./port-forwards.nix network;

  # Convert shared format to NixOS networking.nat.forwardPorts format
  expandProto = fwd:
    if fwd.proto == "both"
    then [(fwd // {proto = "tcp";}) (fwd // {proto = "udp";})]
    else [fwd];

  toLinuxForwardPorts = hosts:
    lib.flatten (lib.mapAttrsToList (
      name: hostCfg:
        lib.flatten (map (fwd:
          map (f: {
            sourcePort = f.port;
            destination = "${hostCfg.ip}:${toString (f.dstPort or f.port)}";
            proto = f.proto;
          }) (expandProto fwd)
        ) hostCfg.forwards)
    ) hosts);
in {
  imports = [./base.nix];

  router.lanInterface = lanBridge;

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

  # Linux-specific: enable IP forwarding (base.nix has common sysctl tuning)
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = true;
    "net.ipv6.conf.all.forwarding" = true;
  };

  # Load flowtable kernel modules
  boot.kernelModules = ["nf_flow_table" "nf_flow_table_inet"];

  # Software flowtable for accelerated forwarding
  # Bypasses full netfilter stack for established connections
  # Note: Can't use networking.nftables.tables because validation fails without devices
  systemd.services.nftables-flowtable = {
    description = "nftables flowtable for accelerated forwarding";
    after = ["nftables.service" "network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.nftables}/bin/nft -f ${pkgs.writeText "flowtable.nft" ''
        table inet flow-offload {
          flowtable f {
            hook ingress priority 0
            devices = { ${wanInterface}, ${lanBridge} }
          }

          chain forward {
            type filter hook forward priority -1; policy accept;
            meta l4proto { tcp, udp } flow add @f counter
          }
        }
      ''}";
      ExecStop = "${pkgs.nftables}/bin/nft delete table inet flow-offload";
    };
  };

  systemd.network = {
    wait-online.enable = true;
    netdevs = {
      "20-${lanBridge}" = {
        netdevConfig = {
          Kind = "bridge";
          Name = lanBridge;
        };
        bridgeConfig = {
          STP = true;
        };
      };
    };
    links = {
      "20-${wanInterface}" = {
        # Match the WAN port by MAC — switchdev recreates the netdev and the
        # default predictable-name rules don't re-fire, leaving it as `eth0`.
        # Driver+MAC survives both that rebuild and PCI path shuffles from
        # other ConnectX cards on Thunderbolt.
        matchConfig = {
          Driver = "mlx5_core";
          PermanentMACAddress = "50:6b:4b:03:04:ca";
        };
        linkConfig = {
          Name = wanInterface;
          RxBufferSize = 8192;
          TxBufferSize = 8192;
        };
      };
      # LAN port (Mellanox CX-4 to Mikrotik 25G). Autoneg + FEC negotiation
      # don't land cleanly on this peer — the link stays down until ethtool
      # forces 25G/no-autoneg and disables FEC. Pin both here so a clean
      # boot brings the bridge up without manual recovery via nanokvm. FEC
      # has no .link option; handled by the lan-25g-fec.service below.
      "20-lan-25g" = {
        matchConfig = {
          Driver = "mlx5_core";
          PermanentMACAddress = "50:6b:4b:03:04:cb";
        };
        linkConfig = {
          Name = "enp1s0f1np1";
          RxBufferSize = 8192;
          TxBufferSize = 8192;
          AutoNegotiation = "no";
          BitsPerSecond = "25G";
          Duplex = "full";
        };
      };
    };
    networks = {
      "10-${lanBridge}" = {
        matchConfig.Name = lanBridge;
        bridgeConfig = {};
        address = [
          (network.cidrOf "lan" network.vlans.lan.gatewayHost)
          "fdde:ad::1/64" # ULA for LAN
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
          Domains = network.domains.lan;
        };
        linkConfig.RequiredFamilyForOnline = "ipv4";
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
      "20-lan-10g-realtek" = {
        matchConfig.Driver = ["r8169" "r8127"];
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

  # Force FEC off on the LAN 25G port. The Mellanox CX-4 ↔ Mikrotik CRS510
  # link won't come up at boot otherwise (peer FEC negotiation is unstable);
  # without this the bridge stays carrierless until manual ethtool recovery.
  systemd.services.lan-25g-fec = {
    description = "Disable FEC on LAN 25G interface";
    bindsTo = ["sys-subsystem-net-devices-enp1s0f1np1.device"];
    after = ["sys-subsystem-net-devices-enp1s0f1np1.device"];
    wantedBy = ["sys-subsystem-net-devices-enp1s0f1np1.device"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.ethtool}/bin/ethtool --set-fec enp1s0f1np1 encoding off";
    };
  };

  # Linux-specific networking (base.nix has common settings)
  networking = {
    nameservers = [network.routerIp];

    nat = {
      enable = true;
      internalIPs = [
        lanCidr
      ];
      internalInterfaces = [
        lanBridge
      ];
      externalInterface = wanInterface;
      forwardPorts = toLinuxForwardPorts portForwardHosts;
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
            37889 # P2Pool P2P (C++ on trex)
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
            37889 # P2Pool P2P (C++ on trex)

            42069 # Snap sync (Bittorrent)

            60001 # mosh
          ];
        };
      };
    };
  };
}
