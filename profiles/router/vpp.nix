{
  config,
  lib,
  pkgs,
  ...
}: let
  interfaces = {
    wan = {
      pci = "0000:01:00.0"; # Mellanox WAN
      name = "wan0";
      mac = "b8:6f:35:ab:31:88";
    };
    lan = {
      mlx = {
        pci = "0000:01:00.1"; # Mellanox 25G
        name = "lan0";
        mac = "b8:6f:35:ab:31:89";
      };
      igc = [
        # {
        #   pci = "0000:05:00.0";
        #   name = "lan1";
        # }
        {
          pci = "0000:06:00.0";
          name = "lan2";
        }
        # {
        #   pci = "0000:07:00.0";
        #   name = "lan3";
        # }
        # {
        #   pci = "0000:08:00.0";
        #   name = "lan4";
        # }
      ];
    };
  };

  # Network configuration
  network = {
    lan = {
      addr = "192.168.23.1";
      prefix = 24;
      mac = "EE:4F:A4:7D:CE:6B";
      network = "192.168.23.0";
    };
    host = {
      interface = "tap0";
      addr = "192.168.23.254";
      mac = "02:fe:1d:4e:4e:73";
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
      ip = "192.168.23.8";
      ports = {
        tcp = [9000];
        udp = [9000 9001];
      };
    };

    # Monero
    monero = {
      ip = "192.168.23.8";
      ports = {
        tcp = [18080];
        udp = [18080];
      };
    };

    # Ethereum nodes
    reth = {
      ip = "192.168.23.8";
      ports = {
        tcp = [30303];
        udp = [30303];
      };
    };

    bitcoind = {
      ip = "192.168.23.8";
      ports = {
        tcp = [8333];
        udp = [8333];
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
  boot.kernelModules = [
    "ipmi_devintf"
    "ipmi_si"
    "tcp_bbr"
    "vfio-pci"
    "igc"
    "igb_uio"
    "uio_pci_generic"
    "mlx5_vfio_pci"
  ];

  users.users.vpp = {
    group = "vpp";
    isSystemUser = true;
  };
  users.groups.vpp = {};

  boot.extraModulePackages = [
    config.boot.kernelPackages.dpdk-kmods
  ];

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
      logRefusedConnections = true;
      logRefusedPackets = true;
      logReversePathDrops = true;
      allowedUDPPorts = [53];
      allowedTCPPorts = [8443];
    };
  };

  boot.kernel.sysctl = {
    # vpp sets this to 2 * 1024 * nr_hugepages, then jellyfin wont start??
    "vm.max_map_count" = lib.mkForce 1048576;
    "net.ipv4.ip_forward" = lib.mkForce false;
    "net.ipv6.conf.all.forwarding" = lib.mkForce false;
    "net.ipv4.conf.all.proxy_arp" = lib.mkForce false;
  };

  systemd.services.dnsmasq.requires = ["vpp-main.service"];
  boot.kernelParams = [
    "intel_iommu=on"
    "amd_iommu=on"
    "iommu=pt"
    # "vfio-pci.ids=15b3:1015" # mlx
    "vfio-pci.ids=8086:125c" # 2.5g
    "nosmt"
    "isolcpus=1-7" # vpp 1 main thread + 4 workers
    "nohz_full=1-7"

    "hugepagesz=1G" # Enable 1GB hugepages
    "hugepages=16" # Allocate 8 of the 1GB hugepages
  ];

  fileSystems."/dev/hugepages-1G" = {
    device = "hugetlbfs";
    fsType = "hugetlbfs";
    options = ["pagesize=1G"];
  };

  services = {
    # inteferes with vpp
    irqbalance.enable = lib.mkForce false;

    vpp = {
      hugepages = {
        autoSetup = true;
        count = 2048;
      };

      instances.main = {
        enable = true;

        package = pkgs.vpp;
        group = "vpp";

        settings = {
          # global-size = {"8G" = true;};
          logging = {
            default-log-level = "info";
            default-syslog-log-level = "info";
          };

          plugins.plugin = {
            # "default".disable = true;

            "dpdk_plugin.so".enable = true;
            "nat_plugin.so".enable = true;
            "ping_plugin.so".enable = true;
            "acl_plugin.so".enable = true;
            "dhcp_plugin.so".enable = true;
            "ip6_nd_plugin.so".enable = true;
            "ip6_ioam_plugin.so".enable = true;

            "prom_plugin.so".enable = true;
            "http_static_plugin.so".enable = true;

            # not working?
            "rdma_plugin.so".disable = true;
          };

          # unix = {
          #   # poll-sleep-usec = 10;
          # };

          ethernet = {
            default-mtu = 1500;
          };

          # heapsize = {
          #   heapsize = "2G";
          # };
          # };
          # ip = {
          #   heap-size = "256M";
          # };

          # nat = {
          #   endpoint-dependent = true;
          #   # "translation hash buckets" = 8096;
          #   # "user hash buckets" = 256;
          # };

          # ip6 = {
          #   # heap-size = "256M";
          #   hash-buckets = 131072;
          # };

          # buffers = {
          #   buffers-per-numa = 256000;
          # };

          cpu = {
            main-core = 1;
            corelist-workers = "2-7";
          };

          # statseg = {
          #   size = "512m";
          # };

          # buffers = {
          #   buffers-per-numa = 128000;
          #   "default data-size" = 2048;
          #   page-size = "default-hugepage";
          # };
          dpdk = {
            ## Disables UDP / TCP TX checksum offload. Typically needed for use
            ## faster vector PMDs (together with no-multi-seg)
            no-tx-checksum-offload = true;

            ## Disable mutli-segment buffers, improves performance but
            ## disables Jumbo MTU support
            no-multi-seg = true;

            ## Increase number of buffers allocated, needed only in scenarios with
            ## large number of interfaces and worker threads. Value is per CPU socket.
            ## Default is 16384
            # num-mbufs = "131072";

            dev =
              {
                # default = {
                # };

                # WAN interface
                ${interfaces.wan.pci} = {
                  name = interfaces.wan.name;
                  num-rx-desc = 256;
                  num-tx-desc = 256;
                  # num-rx-queues = 6;
                  # num-rx-desc = 4096;
                  # num-tx-desc = 4096;
                };

                # Mellanox 25G LAN
                ${interfaces.lan.mlx.pci} = {
                  name = interfaces.lan.mlx.name;
                  num-rx-desc = 256;
                  num-tx-desc = 256;
                  # num-rx-queues = 6;
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
                    num-rx-desc = 256;
                    num-tx-desc = 256;
                    # uio-driver = "igc_uio";
                    # num-rx-queues = 1;
                    # num-tx-queues = 1;
                    # num-rx-desc = 512;
                    # num-tx-desc = 512;
                  };
                })
                interfaces.lan.igc
              );
          };
        };

        startupConfig = ''
          # set nat frame-queue-nelts 2048

          # wan0 setup
          set int mac address ${interfaces.wan.name} ${interfaces.wan.mac}
          set dhcp client intfc ${interfaces.wan.name} hostname gateway
          set interface state ${interfaces.wan.name} up

          # BVI Setup
          bvi create instance 0
          set int mac address bvi0 ${network.lan.mac}

          set interface l2 bridge bvi0 1 bvi
          set interface ip address bvi0 ${network.lan.addr}/${toString network.lan.prefix}
          set interface state bvi0 up

          # Set up LAN IPv4
          set interface l2 bridge ${interfaces.lan.mlx.name} 1
          set interface state ${interfaces.lan.mlx.name} up

          # 2.5G interfaces (IPv6 disabled for debugging)
          ${
            lib.concatMapStrings
            (iface: ''
              # IPv4 only configuration
              # set interface l2 bridge ${iface.name} 1
              set interface state ${iface.name} up
              # enable ip6 interface ${iface.name}
            '')
            interfaces.lan.igc
          }

          # Create and configure host tap
          create tap host-if-name ${network.host.interface} host-ip4-addr ${network.host.addr}/${toString network.host.prefix} host-ip4-gw ${network.lan.addr}
          set interface l2 bridge ${network.host.interface} 1
          # set interface nat44 in ${network.host.interface}
          # enable ip6 interface ${network.host.interface}
          # set interface mtu packet 1500 ${network.host.interface}
          set interface state ${network.host.interface} up

          # set interface nat44 in bvi0
          # create bridge-domain 1 arp-term 1 mac-age 60 ip6-nd 1 learn 0 forward 1 uu-flood 0

          # Set up WAN IPv4
          # set interface mtu packet 1500 ${interfaces.wan.name}
          # set interface nat44 out ${interfaces.wan.name} output-feature

          # Set up WAN
          set interface ip6 table ${interfaces.wan.name} 0
          ip6 nd address autoconfig ${interfaces.wan.name} default-route
          dhcp6 client ${interfaces.wan.name}
          dhcp6 pd client ${interfaces.wan.name} prefix group hgw

          # BVI Setup IPv6
          # enable ip6 interface bvi0
          set ip6 address bvi0 prefix group hgw ::1/64
          ip6 nd address autoconfig bvi0 default-route
          ip6 nd bvi0 ra-managed-config-flag ra-other-config-flag ra-interval 30 20 ra-lifetime 180

          # enable NAT plugin
          nat44 forwarding enable
          nat44 plugin enable sessions 200000
          # set interface nat44 in bvi0 out ${interfaces.wan.name}
          nat44 add interface address ${interfaces.wan.name}
          set interface nat44 in ${interfaces.wan.name} output-feature

          # Port forwarding rules
          ${generateNatRules portForwards}
        '';
      };
    };
  };
}
