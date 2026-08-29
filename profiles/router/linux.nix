{config, lib, pkgs, network, ...}: let
  routerPorts = network.ports.router;
  legacyPcieNetwork = config.router.legacyPcieNetwork.enable;
  onboardLanPorts = routerPorts.onboardLan;
  wanPort = routerPorts.wan;
  lan25gPort = routerPorts.lan25g;
  lan10gPort = routerPorts.lan10g;
  wanInterface = wanPort.linuxName;
  lan25gInterface = lan25gPort.linuxName;
  lan10gInterface = lan10gPort.linuxName;
  lanBridge = routerPorts.lanBridge;
  lanMtu = toString network.vlans.lan.mtu;
  lanCidr = "${network.vlans.lan.prefix}.0/${toString network.vlans.lan.cidr}";
  fabricCidr = "${network.vlans.fabric.prefix}.0/${toString network.vlans.fabric.cidr}";

  # Wi-Fi client VLAN (tagged 50): an SVI on the LAN bridge. Tagged frames from
  # the AP (rock-5b) ride the flat switch as an overlay and terminate here.
  wifiVlan = network.vlans.wifi;
  wifiVlanIf = "${lanBridge}.${toString wifiVlan.id}";
  wifiCidr = "${wifiVlan.prefix}.0/${toString wifiVlan.cidr}";
  wifiMtu = "1500";
  wifiUla = "fdde:ad:${toString wifiVlan.id}";

  bridgeMemberNetwork = matchConfig: requiredForOnline: {
    inherit matchConfig;
    networkConfig.Bridge = lanBridge;
    linkConfig = {
      MTUBytes = lanMtu;
      RequiredForOnline = requiredForOnline;
    };
  };

  onboardLanLinks = lib.listToAttrs (map (port: {
    name = "10-router-${port.linuxName}";
    value = {
      matchConfig = {
        Driver = "igc";
        PermanentMACAddress = port.mac;
      };
      linkConfig = {
        Name = port.linuxName;
        MTUBytes = lanMtu;
      };
    };
  }) onboardLanPorts);

  onboardLanNetworks = lib.listToAttrs (map (port: {
    name = "10-router-${port.linuxName}";
    value = bridgeMemberNetwork {
      Name = port.linuxName;
      PermanentMACAddress = port.mac;
    } "no";
  }) onboardLanPorts);

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
  imports = [
    ./base.nix
  ];

  router.lanInterface = lanBridge;

  services.usbmuxd.enable = true;
  # Include the WiFi VLAN so the avahi reflector (homekit.nix) can bridge
  # mDNS between wired LAN and wireless clients (HomeKit, ESPHome discovery).
  services.avahi.allowInterfaces = lib.mkForce [lanBridge wifiVlanIf];

  # WAN hardening: profiles/home.nix opens the metrics exporters on all
  # interfaces, but on the router that includes the internet. Keep them
  # LAN-only (victoriametrics on trex scrapes over the LAN bridge).
  services.prometheus.exporters.node.openFirewall = lib.mkForce false;
  services.prometheus.exporters.zfs.openFirewall = lib.mkForce false;
  services.prometheus.exporters.smartctl.openFirewall = lib.mkForce false;
  networking.firewall.interfaces."${lanBridge}".allowedTCPPorts = [
    5201 # iperf3
    9100 # node-exporter
    9134 # zfs-exporter
    9633 # smartctl-exporter
  ];

  # Inbound IPv6 from the WAN is deliberately NOT filtered here: end-to-end
  # v6 is wanted, and each machine is responsible for its own firewall.

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
  # Disabled: it breaks Wi-Fi VLAN clients in practice. iOS clients complete
  # DHCP/DNS/TCP setup, then stall once larger TLS payloads enter the flowtable.
  # Note: Can't use networking.nftables.tables because validation fails without devices
  systemd.services.nftables-flowtable = {
    enable = false;
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

  # mlx5 + this MikroTik combo is finicky: applying speed/autoneg/duplex via
  # systemd-networkd's .link file is hit-or-miss — some boots the link trains,
  # some it doesn't and needs a manual `ip link down/up` + ethtool to settle.
  # 2026-07-16: after a crash-reboot the old recipe (autoneg on, fec off) would
  # not train at all despite good light both directions; forced no-autoneg +
  # RS-FEC trained instantly. Empirically the reliable sequence is:
  #   ip link set <iface> down
  #   ethtool -s <iface> autoneg off speed 25000 duplex full
  #   ethtool --set-fec <iface> encoding rs
  #   ip link set <iface> up
  # which we run as a single oneshot service. MikroTik side is force 25G:
  #   /interface ethernet set sfp28-1 \
  #     auto-negotiation=no speed=25G-baseSR-LR fec-mode=fec91
  systemd.services.lan-25g-link-config = lib.mkIf legacyPcieNetwork {
    description = "Configure LAN 25G interface link (speed/autoneg/FEC)";
    after = ["sys-subsystem-net-devices-${lan25gInterface}.device"];
    bindsTo = ["sys-subsystem-net-devices-${lan25gInterface}.device"];
    wants = ["sys-subsystem-net-devices-${lan25gInterface}.device"];
    before = ["systemd-networkd.service" "network-pre.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.iproute2}/bin/ip link set ${lan25gInterface} down
      ${pkgs.ethtool}/bin/ethtool -s ${lan25gInterface} autoneg off speed 25000 duplex full
      ${pkgs.ethtool}/bin/ethtool --set-fec ${lan25gInterface} encoding rs
      ${pkgs.iproute2}/bin/ip link set ${lan25gInterface} up
    '';
  };

  systemd.network = {
    wait-online.enable = true;
    netdevs = {
      "20-${lanBridge}" = {
        netdevConfig = {
          Kind = "bridge";
          Name = lanBridge;
          MTUBytes = lanMtu;
        };
        bridgeConfig = {
          STP = true;
          # Default forward-delay is 15s, applied twice (listening → learning →
          # forwarding) which adds 30s to network-online.target at every boot.
          # Loop topology here is fixed and trusted, so we still want STP for
          # the safety net but the long delays buy us nothing.
          ForwardDelaySec = 2;
        };
      };
      # Wi-Fi client VLAN SVI (tagged 50) on top of the LAN bridge.
      "30-${wifiVlanIf}" = {
        netdevConfig = {
          Kind = "vlan";
          Name = wifiVlanIf;
        };
        vlanConfig.Id = wifiVlan.id;
      };
    };
    links = onboardLanLinks // lib.optionalAttrs legacyPcieNetwork {
      "20-${wanInterface}" = {
        # Match the WAN port by MAC — switchdev recreates the netdev and the
        # default predictable-name rules don't re-fire, leaving it as `eth0`.
        # Driver+MAC survives both that rebuild and PCI path shuffles from
        # other ConnectX cards on Thunderbolt.
        matchConfig = {
          Driver = "mlx5_core";
          PermanentMACAddress = wanPort.mac;
        };
        linkConfig = {
          Name = wanInterface;
          RxBufferSize = 8192;
          TxBufferSize = 8192;
        };
      };
      # LAN port (Mellanox CX-4 to MikroTik CRS510, 25G optical). Only Name +
      # buffers here — speed/autoneg/duplex/FEC are applied by the
      # lan-25g-link-config service after the netdev appears, because doing
      # them via .link is unreliable on this mlx5/MikroTik combo.
      "20-lan-25g" = {
        matchConfig = {
          Driver = "mlx5_core";
          PermanentMACAddress = lan25gPort.mac;
        };
        linkConfig = {
          Name = lan25gInterface;
          RxBufferSize = 8192;
          TxBufferSize = 8192;
          MTUBytes = lanMtu;
        };
      };
      # RTL8127 10G copper — pinned by MAC because its bus-drop flap renames it
      # (enp2s0/enp7s0) across boots; see network.nix ports.router.lan10g.
      "20-lan-10g" = {
        matchConfig = {
          Driver = "r8127";
          PermanentMACAddress = lan10gPort.mac;
        };
        linkConfig.Name = lan10gInterface;
      };
    };
    networks = {
      "10-${lanBridge}" = {
        matchConfig.Name = lanBridge;
        # Attach the Wi-Fi VLAN SVI to the bridge.
        vlan = [wifiVlanIf];
        bridgeConfig = {};
        address = [
          (network.cidrOf "lan" network.vlans.lan.gatewayHost)
          # Secondary service address for the VPP gateway handoff. It is
          # brought up and tested while this host still owns .1; later .1
          # moves to BlueField and DNS/DHCP/netboot remain reachable here.
          (network.cidrOf "lan" network.routing.production.transition.controlPlane.targetHost)
          "${network.routing.production.transition.controlPlane.targetIpv6}/64"
          "fdde:ad::1/64" # ULA for LAN
        ];
        routes = [
          {
            Destination = fabricCidr;
            Gateway = network.primaryIp network.hosts."mikrotik-crs812";
          }
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
        linkConfig = {
          MTUBytes = lanMtu;
          RequiredFamilyForOnline = "ipv4";
        };
      };
      # Wi-Fi client VLAN gateway (192.168.50.1). Routed + NAT'd like the LAN;
      # "trusted" so wifi<->lan forwarding is allowed (no isolation ACL).
      "30-${wifiVlanIf}" = {
        matchConfig.Name = wifiVlanIf;
        address = [
          (network.cidrOf "wifi" wifiVlan.gatewayHost)
          "${wifiUla}::1/64"
        ];
        networkConfig = {
          ConfigureWithoutCarrier = true;
          DHCPPrefixDelegation = true;
          IPv6Forwarding = true;
          IPv6SendRA = true;
        };
        dhcpPrefixDelegationConfig = {
          SubnetId = toString wifiVlan.id;
          Announce = true;
        };
        ipv6SendRAConfig = {
          Managed = false;
          EmitDNS = true;
          DNS = ["${wifiUla}::1"];
          Domains = network.domains.lan;
        };
        linkConfig = {
          MTUBytes = wifiMtu;
          RequiredForOnline = "no";
        };
      };

    } // onboardLanNetworks // lib.optionalAttrs legacyPcieNetwork {
      "20-lan-25g" = bridgeMemberNetwork {Name = lan25gInterface;} "enslaved";
      "20-lan-10g" = bridgeMemberNetwork {Driver = "atlantic";} "no";
      "20-lan-10g-realtek" = bridgeMemberNetwork {Driver = ["r8169" "r8127"];} "no";
      "20-thunderbolt-mlx5-0" = bridgeMemberNetwork {
        Driver = "mlx5_core";
        Path = "pci-0000:0b:*";
      } "no";
      "20-thunderbolt-mlx5-1" = bridgeMemberNetwork {
        Driver = "mlx5_core";
        Path = "pci-0000:0c:*";
      } "no";
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
        # Don't block network-online.target on IPv6 DHCP-PD — IPv4 lands in
        # seconds, IPv6-PD often takes 30 s+. Saves boot time.
        linkConfig.RequiredFamilyForOnline = "ipv4";
      };
    } // {
      # WireGuard tunnels don't need to be "online" for the router to be up.
      # Default is RequiredForOnline=yes, which makes wait-online block on
      # peer reachability.
      "40-wg-home".linkConfig.RequiredForOnline = "no";
      "40-wg-hydra-bld".linkConfig.RequiredForOnline = "no";
    };
  };

  # A rename storm can make networkd permanently leave a port unmanaged for
  # that boot (observed on all four I226-V ports on 2026-08-29). The .link and
  # .network files above are the normal path; this idempotent MAC-based pass
  # reconciles the desired bridge membership without depending on the name.
  systemd.services.onboard-lan-bridge-reconcile = {
    description = "Reconcile the on-board Intel LAN ports with the LAN bridge";
    after = ["systemd-networkd.service"];
    before = ["dnsmasq.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.coreutils pkgs.iproute2];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for attempt in $(seq 1 30); do
        [ -e /sys/class/net/${lanBridge} ] && break
        sleep 1
      done
      if [ ! -e /sys/class/net/${lanBridge} ]; then
        echo "LAN bridge ${lanBridge} did not appear" >&2
        exit 1
      fi

      ${lib.concatMapStringsSep "\n" (port: ''
        found=""
        for sys_path in /sys/class/net/*; do
          [ -r "$sys_path/address" ] || continue
          [ "$(tr '[:upper:]' '[:lower:]' < "$sys_path/address")" = "${port.mac}" ] || continue
          interface="$(basename "$sys_path")"
          ip link set dev "$interface" mtu ${lanMtu}
          ip link set dev "$interface" up
          ip link set dev "$interface" master ${lanBridge}
          echo "${port.mac}: $interface joined ${lanBridge} (declared name ${port.linuxName})"
          found=1
          break
        done
        if [ -z "$found" ]; then
          echo "Expected on-board LAN port ${port.mac} (${port.linuxName}) is absent" >&2
          exit 1
        fi
      '') onboardLanPorts}
    '';
  };


  # Linux-specific networking (base.nix has common settings)
  networking = {
    nameservers = [network.dnsIp];

    nat = {
      enable = true;
      internalIPs = [
        lanCidr
        fabricCidr
        wifiCidr
      ];
      internalInterfaces = [
        lanBridge
        wifiVlanIf
      ];
      externalInterface = wanInterface;
      forwardPorts = toLinuxForwardPorts portForwardHosts;
    };

    firewall = {
      enable = true;
      checkReversePath = false;
      trustedInterfaces = [lanBridge "wg-home" wifiVlanIf];
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

            30303 # geth

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

            30303 # geth

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
