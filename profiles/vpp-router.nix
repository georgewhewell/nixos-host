{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  interfaces = {
    wan = {
      pci = "0000:01:00.0"; # Mellanox WAN
      name = "wan0";
    };
    lan = {
      mlx = {
        pci = "0000:01:00.1"; # Mellanox 25G
        name = "lan0";
      };
      igc = [
        {
          pci = "0000:05:00.0";
          name = "lan1";
        }
        {
          pci = "0000:06:00.0";
          name = "lan2";
        }
        {
          pci = "0000:07:00.0";
          name = "lan3";
        }
        {
          pci = "0000:08:00.0";
          name = "lan4";
        }
      ];
    };
  };

  # Network configuration
  network = {
    lan = {
      addr = "192.168.23.1";
      prefix = 24;
      network = "192.168.23.0";
    };
    host = {
      interface = "tap0";
      addr = "192.168.23.254";
      prefix = 24;
    };
  };

  portForwards = {
    # Transmission
    transmission = {
      ip = "192.168.23.5";
      ports = {
        tcp = [51413];
        udp = [51413];
      };
    };

    # qBittorrent
    qbittorrent = {
      ip = "192.168.23.5";
      ports = {
        tcp = [17026];
        udp = [17026];
      };
    };

    # Lighthouse
    lighthouse = {
      ip = "192.168.23.5";
      ports = {
        tcp = [9000 9001 9002];
        udp = [9000 9001 9002];
      };
    };

    # Monero
    monero = {
      ip = "192.168.23.5";
      ports = {
        tcp = [18080];
        udp = [18080];
      };
    };

    # Ethereum nodes
    ethereum = {
      ip = "192.168.23.5";
      ports = {
        tcp = [30303 30304 4001];
        udp = [30303 30304 4001];
      };
    };

    nginx = {
      ip = "192.168.23.254";
      ports = {
        tcp = [80 443];
      };
    };

    ssh = {
      ip = "192.168.23.254";
      ports = {
        tcp = [22];
      };
    };

    # Other services
    other = {
      ip = "192.168.23.5";
      ports = {
        tcp = [8333 8776]; # Bitcoin and Radicle
      };
    };
  };

  generateNatRules = forwards:
    lib.concatStrings (lib.flatten (
      lib.mapAttrsToList (
        name: cfg:
        # Generate TCP rules
          (map (port: ''
            nat44 add static mapping tcp local ${cfg.ip} ${toString port} external ${interfaces.wan.name} ${toString port}
          '') (cfg.ports.tcp or []))
          ++
          # Generate UDP rules
          (map (port: ''
            nat44 add static mapping udp local ${cfg.ip} ${toString port} external ${interfaces.wan.name} ${toString port}
          '') (cfg.ports.udp or []))
      )
      forwards
    ));
in {
  boot.initrd.kernelModules = [
    "nf_tables"
    "nft_compat"
    "i40e"
    "ice"
  ];

  boot.kernelModules = [
    "ipmi_devintf"
    "ipmi_si"
    "tcp_bbr"
    "vfio-pci"
  ];

  users.users.vpp = {
    group = "vpp";
    isSystemUser = true;
  };

  users.groups.vpp = {};

  boot.extraModulePackages = [
    config.boot.kernelPackages.dpdk-kmods
  ];

  environment.systemPackages = with pkgs; [
    pciutils
    btop
    wirelesstools
    bridge-utils
    ethtool
    tcpdump
    conntrack-tools
    pciutils
    iperf
    vpp
  ];

  boot.kernelParams = [
    "intel_iommu=on"
    "amd_iommu=on"
    "iommu=pt"
    # "vfio-pci.ids=15b3:1015"
    "nosmt"
    "isolcpus=1-5" # vpp 1 main thread + 4 workers
    "nohz_full=1-5"
  ];

  services = {
    vpp = {
      hugepages = {
        autoSetup = true;
        count = 1024;
      };

      instances.main = {
        enable = true;
        group = "vpp";

        settings = {
          # logging = {
          #   default-log-level = "debug";
          #   default-syslog-log-level = "debug";
          # };
          dpdk = {
            dev =
              {
                # default = {
                # };

                # WAN interface
                ${interfaces.wan.pci} = {
                  name = interfaces.wan.name;
                  num-rx-queues = 4;
                  # num-rx-desc = 4096;
                  # num-tx-desc = 4096;
                };

                # Mellanox 25G LAN
                ${interfaces.lan.mlx.pci} = {
                  name = interfaces.lan.mlx.name;
                  num-rx-queues = 4;
                  # num-rx-desc = 4096;
                  # num-tx-desc = 4096;
                };
              }
              # Intel 2.5G interfaces
              // builtins.listToAttrs (
                map
                (iface: {
                  name = iface.pci;
                  value = {
                    name = iface.name;
                    # num-rx-queues = 4;
                  };
                })
                interfaces.lan.igc
              );
          };

          cpu = {
            main-core = 0;
            workers = 4;
          };
          statseg = {
            size = "512m"; # Adjust size as needed
            # per-node-counters = "on";
          };
          # stats = {
          #   statseg-sw-interface-prefix = "all";
          # };

          plugins.plugin = {
            "dpdk_plugin.so".enable = true;
            "nat_plugin.so".enable = true;
            "acl_plugin.so".enable = true;
            "dhcp_plugin.so".enable = true;
            "ip6_nd_plugin.so".enable = true;
            "ip6_ioam_plugin.so".enable = true;

            "prom_plugin.so".enable = true;
            "http_static_plugin.so".enable = true;

            # not working?
            "rdma_plugin.so".disable = true;
          };

          # tuntap = {
          #   enable = true;
          #   name = network.host.interface;
          # };
        };

        startupConfig = ''
          # enable prometheus metrics
          prom enable

          # enable NAT plugin
          nat44 plugin enable sessions 63000
          nat44 forwarding enable

          # Create bridge domain
          create bridge-domain 1 arp-term 1 mac-age 60 ip6-nd 1

          # Set up WAN IPv4
          set dhcp client intfc ${interfaces.wan.name} hostname gateway
          nat44 add interface address ${interfaces.wan.name}
          set interface nat44 out ${interfaces.wan.name} output-feature

          # Set up LAN IPv4
          set interface l2 bridge ${interfaces.lan.mlx.name} 1
          set interface nat44 in ${interfaces.lan.mlx.name}
          enable ip6 interface ${interfaces.lan.mlx.name}
          set interface state ${interfaces.lan.mlx.name} up

          # Set up WAN IPv6 first
          set interface state ${interfaces.wan.name} up
          set interface ip6 table ${interfaces.wan.name} 0
          ip6 nd address autoconfig ${interfaces.wan.name} default-route
          dhcp6 client ${interfaces.wan.name}
          dhcp6 pd client ${interfaces.wan.name} prefix group hgw

          # BVI Setup
          bvi create instance 0
          set interface l2 bridge bvi0 1 bvi
          set interface ip address bvi0 ${network.lan.addr}/${toString network.lan.prefix}
          set interface nat44 in bvi0

          # BVI Setup IPv6
          enable ip6 interface bvi0
          set ip6 address bvi0 prefix group hgw ::1/64
          ip6 nd address autoconfig bvi0 default-route
          ip6 nd bvi0 ra-managed-config-flag ra-other-config-flag ra-interval 30 20 ra-lifetime 180
          set interface state bvi0 up

          # 2.5G interfaces
          ${
            lib.concatMapStrings
            (iface: ''
              # set interface l2 bridge ${iface.name} 1
              # set interface nat44 in ${iface.name}
              # enable ip6 interface ${iface.name}
              # set interface state ${iface.name} up
            '')
            []
            # interfaces.lan.igc
          }

          # Create and configure host tap
          create tap host-if-name ${network.host.interface} host-ip4-addr ${network.host.addr}/${toString network.host.prefix} host-ip4-gw ${network.lan.addr}
          set interface l2 bridge ${network.host.interface} 1
          set interface nat44 in ${network.host.interface}
          enable ip6 interface ${network.host.interface}
          set interface state ${network.host.interface} up

          # Port forwarding rules
          ${generateNatRules portForwards}
        '';
      };
    };
  };

  services.dnscrypt-proxy2 = {
    enable = true;
    settings = {
      listen_addresses = ["127.0.0.1:54"];
      static.cloudflare = {
        stamp = "sdns://AgcAAAAAAAAABzEuMC4wLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5";
      };
    };
  };

  systemd.services.dnsmasq.requires = ["vpp-main.service"];

  services.dnsmasq = {
    enable = true;
    servers = ["127.0.0.1#54"];
    settings = {
      domain-needed = true;
      bogus-priv = true;
      no-resolv = true;
      no-hosts = true;
      log-dhcp = true;
      enable-ra = true;
      domain = "lan.satanic.link";
      local = "/lan.satanic.link/";
      bind-dynamic = true;
      interface = network.host.interface;
      except-interface = "lo";
      "dhcp-range" = "${network.host.interface},192.168.23.20,192.168.23.249,6h";
      "dhcp-option" = [
        "${network.host.interface},3,192.168.23.1"
        "option6:23,[::]"
      ];
      "dhcp-host" = [
        "e4:8d:8c:a8:de:40,192.168.23.2" # 10gb switch
        "80:2a:a8:80:96:ef,192.168.23.3" # ap
        "0c:c4:7a:89:fb:37,192.168.23.4" # x10 ipmi
        "0c:c4:7a:87:b9:d8,192.168.23.5" # nixhost
        "78:11:dc:ec:86:ea,192.168.23.6" # vacuum
        "50:6b:4b:03:04:cb,192.168.23.8" # trex
        "48:A9:8A:93:42:4C,192.168.23.9" # 100gb switch
        "9c:6b:00:57:31:77,192.168.23.10" # trx90bmc
        "28:29:86:8b:3f:cb,192.168.23.11" # apc ups
        "b4:22:00:cf:18:63,192.168.23.12" # printer
        "c8:f0:9e:de:3c:2f,192.168.23.13" # cerberus
        "90:e2:ba:1a:69:d8,192.168.23.14" # jellyfin (10g)
        "fa:09:ef:0e:74:d7,192.168.23.15" # sonarr
        "fa:48:90:8d:03:d0,192.168.23.16" # radarr
        "38:7A:CC:40:41:E3,192.168.23.17" # nanokvm (router)
        "00:e0:4c:68:02:e7,192.168.23.18" # rock-5b (router)
      ];
      "address" = [
        "/router.satanic.link/192.168.23.254"
        "/nixhost.satanic.link/192.168.23.5"
        "/trex.satanic.link/192.168.23.8"
        "/jellyfin.satanic.link/192.168.23.254"
        "/grafana.satanic.link/192.168.23.254"
        "/home.satanic.link/192.168.23.254"
        "/radarr.satanic.link/192.168.23.254"
        "/sonarr.satanic.link/192.168.23.254"
        "/eth-mainnet.satanic.link/192.168.23.254"
        "/eth-mainnet-ws.satanic.link/192.168.23.254"
        "/static.satanic.link/192.168.23.254"
        "/gateway.satanic.link/192.168.23.1"
      ];
    };
  };

  # systemd.services."systemd-networkd-wait-online" = {
  #   serviceConfig.ExecStart = [
  #     "" # Clear the existing ExecStart
  #     "${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online --interface=${lanBridge}"
  #   ];
  # };

  systemd.network = {
    wait-online.enable = true;
    # netdevs = {
    #   "20-${lanBridge}" = {
    #     netdevConfig = {
    #       Kind = "bridge";
    #       Name = lanBridge;
    #     };
    #   };
    # };
    # networks = {
    #   "10-${lanBridge}" = {
    #     matchConfig.Name = lanBridge;
    #     bridgeConfig = {};
    #     address = [
    #       "192.168.23.254/24"
    #     ];
    #     networkConfig = {
    #       ConfigureWithoutCarrier = true;
    #       # DHCPPrefixDelegation = true;
    #       # IPv6AcceptRA = false;
    #       # IPv6SendRA = true;
    #       # IPv6Forwarding = true;
    #       # IPv6PrivacyExtensions = true;
    #     };
    #     linkConfig.RequiredForOnline = "routable";
    #   };
    #   "20-tap0" = {
    #     matchConfig.Name = "tap0";
    #     networkConfig.Bridge = lanBridge;
    #     linkConfig.RequiredForOnline = "enslaved";
    #   };
    #   "20-lan-2-5g" = {
    #     matchConfig.Driver = "igc";
    #     networkConfig.Bridge = lanBridge;
    #     linkConfig.RequiredForOnline = "enslaved";
    #   };
    # };
  };

  # mostly managed by vpp, but use networkd alongside for recovery net
  networking = {
    useDHCP = false;
    enableIPv6 = true;
    useNetworkd = true;
    nftables.enable = true;
    domain = "lan.satanic.link";
    nameservers = ["192.168.23.254"];

    firewall = {
      enable = false;
      checkReversePath = false;
      # trustedInterfaces = [network.host.interface];
      logRefusedConnections = true;
      logRefusedPackets = true;
      logReversePathDrops = true;
      allowedUDPPorts = [53];
      allowedTCPPorts = [8443];
    };
  };

  # services.miniupnpd = {
  #   enable = true;
  #   externalInterface = wanInterface;
  #   internalIPs = [lanBridge];
  #   natpmp = true;
  #   upnp = true;
  # };

  services.avahi = {
    enable = true;
    reflector = true;
    interfaces = lib.mkForce [
      "tap0"
    ];
  };

  # services.fail2ban.enable = true;

  services.prometheus.exporters = {
    # dnsmasq.enable = true;
  };
}
