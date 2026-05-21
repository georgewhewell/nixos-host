# VPP-based router data plane
# - 25G Mellanox ports via RDMA (WAN + LAN)
# - 4x Intel I226-V switch ports via AF_XDP (lan1-lan4)
# Recovery: NanoKVM at 10.86.167.1 via USB (enp202s0f3u1)
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Import shared port forward definitions
  portForwardHosts = import ./port-forwards.nix;

  # Convert shared format to VPP nat44 static mapping commands
  expandProto = fwd:
    if fwd.proto == "both"
    then [(fwd // {proto = "tcp";}) (fwd // {proto = "udp";})]
    else [fwd];

  toVppNatRules = wanIface: hosts:
    lib.concatStrings (lib.flatten (lib.mapAttrsToList (
        name: hostCfg:
          if name == "router"
          then []
          else # Skip router entry (handled by hairpin rules)
            lib.flatten (map (
                fwd:
                  map (f: ''
                    nat44 add static mapping ${f.proto} local ${hostCfg.ip} ${toString (f.dstPort or f.port)} external ${wanIface} ${toString f.port}
                  '') (expandProto fwd)
              )
              hostCfg.forwards)
      )
      hosts));

  # Generate LAN hairpin NAT rules for router local services (.1 -> .254)
  toVppHairpinRules = lanAddr: routerCfg:
    lib.concatStrings (lib.flatten (map (
        fwd:
          map (f: ''
            nat44 add static mapping ${f.proto} local ${routerCfg.ip} ${toString f.port} external ${lanAddr} ${toString f.port}
          '') (expandProto fwd)
      )
      routerCfg.forwards));

  # Hardware - 25G Mellanox ports (RDMA)
  wan = {
    linux = "enp1s0f0np0"; # Linux interface name (RDMA needs this)
    name = "wan0"; # VPP interface name
    mac = "50:6b:4b:03:04:ca";
  };

  lan = {
    linux = "enp1s0f1np1";
    name = "lan0";
    mac = "50:6b:4b:03:04:cb";
  };

  lan2 = {
    linux = "enp2s0";
    name = "rtk0";
    # mac = "50:6b:4b:03:04:cb";
  };

  # Thunderbolt Mellanox 25G ports (RDMA)
  thunderboltPorts = [
    {
      linux = "ens1f0np0";
      name = "tb0";
      mac = "50:6b:4b:46:dd:9c";
    }
    {
      linux = "ens1f1np1";
      name = "tb1";
      mac = "50:6b:4b:46:dd:9d";
    }
  ];

  # Intel I226-V switch ports (AF_XDP)
  switchPorts = [
    {
      linux = "enp5s0";
      name = "lan1";
    }
    {
      linux = "enp6s0";
      name = "lan2";
    }
    {
      linux = "enp7s0";
      name = "lan3";
    }
    {
      linux = "enp9s0";
      name = "lan4";
    }
  ];

  # Realtek RTL8127 10GbE (AF_XDP)
  realtekPort = {
    linux = "enp2s0";
    name = "rtk0";
  };

  # Network configuration
  network = {
    lan = {
      addr = "192.168.23.1";
      prefix = 24;
    };
    host = {
      bridge = "br-lan"; # Linux bridge for tap0 + Realtek
      tap = "tap0";
      addr = "192.168.23.254";
      prefix = 24;
    };
  };
in {
  imports = [./base.nix];

  router.lanInterface = network.host.bridge;

  # RDMA needs these modules
  boot.kernelModules = [
    "mlx5_core"
    "mlx5_ib"
    "ib_uverbs"
  ];

  # Isolate CPUs 2-7 for VPP (+ SMT siblings 10-15 kept idle)
  # Linux gets cores 0-1 with SMT (threads 0,1,8,9)
  boot.kernelParams = [
    "amd_iommu=on"
    "iommu=pt"

    # 2MB hugepages for DPDK (must come before 1G definition)
    "hugepagesz=2M"
    "hugepages=8192"

    # 1GB hugepages
    # "hugepagesz=1G"
    # "hugepages=16"

    # "default_hugepagesz=1GB"

    "isolcpus=2-7,10-15"
    "nohz_full=2-7,10-15"
    "rcu_nocbs=2-7,10-15"
  ];

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Add any missing dynamic libraries for unpackaged programs

    # here, NOT in environment.systemPackages
    stdenv.cc.cc.lib
  ];

  systemd.mounts = [
    # {
    #   what = "hugetlbfs";
    #   where = "/dev/hugepages-1G";
    #   type = "hugetlbfs";
    #   options = "pagesize=1G";
    #   wantedBy = ["multi-user.target"];
    # }
    {
      what = "hugetlbfs";
      where = "/dev/hugepages";
      type = "hugetlbfs";
      options = "pagesize=2M";
      wantedBy = ["multi-user.target"];
    }
  ];

  systemd.tmpfiles.rules = [
    "d /dev/hugepages    0755 root root -"
    "d /dev/hugepages-2M 0755 root root -"
  ];

  users.users.vpp = {
    group = "vpp";
    isSystemUser = true;
  };
  users.groups.vpp = {};

  # VPP-specific networking
  networking = {
    nameservers = ["192.168.23.254"];
    firewall.enable = false;
    nat.enable = false;
  };

  # Explicitly deconfigure Mellanox interfaces - VPP manages them via RDMA
  # Using high priority (00-) to override any other config
  systemd.network.networks =
    {
      # WAN - no IP, no DHCP, just bring up for VPP RDMA
      "00-vpp-wan" = {
        matchConfig.Name = wan.linux;
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
        linkConfig.RequiredForOnline = "no";
      };
      # LAN - no IP, no bridge, just bring up for VPP RDMA (jumbo MTU for performance)
      "00-vpp-lan" = {
        matchConfig.Name = lan.linux;
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
          # Explicitly NOT in a bridge
        };
        linkConfig = {
          RequiredForOnline = "no";
          MTUBytes = "9000";
        };
      };
    }
    # Intel I226-V switch ports - add to Linux bridge
    // lib.listToAttrs (map (port: {
        name = "10-${port.name}-bridge";
        value = {
          matchConfig.Name = port.linux;
          networkConfig = {
            Bridge = network.host.bridge;
            LinkLocalAddressing = "no";
          };
          linkConfig.RequiredForOnline = "no";
        };
      })
      switchPorts)
    // lib.listToAttrs (map (port: {
        name = "00-vpp-${port.name}";
        value = {
          matchConfig.Name = port.linux;
          networkConfig = {
            DHCP = "no";
            LinkLocalAddressing = "no";
            IPv6AcceptRA = false;
          };
          linkConfig.RequiredForOnline = "no";
        };
      })
      thunderboltPorts)
    // {
      # Realtek 10GbE - add to Linux bridge (not VPP)
      "10-realtek-bridge" = {
        matchConfig.Name = realtekPort.linux;
        networkConfig = {
          Bridge = network.host.bridge;
          LinkLocalAddressing = "no";
        };
        linkConfig.RequiredForOnline = "no";
      };
      # tap0 from VPP - add to Linux bridge
      "10-tap-bridge" = {
        matchConfig.Name = network.host.tap;
        networkConfig = {
          Bridge = network.host.bridge;
          LinkLocalAddressing = "no";
        };
        linkConfig.RequiredForOnline = "no";
      };
      # Linux bridge - gets the host IP
      "10-br-lan" = {
        matchConfig.Name = network.host.bridge;
        networkConfig = {
          Address = "${network.host.addr}/${toString network.host.prefix}";
          Gateway = network.lan.addr;
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
        linkConfig.RequiredForOnline = "no";
      };
    };

  # Create the Linux bridge netdev
  systemd.network.netdevs."10-br-lan" = {
    netdevConfig = {
      Name = network.host.bridge;
      Kind = "bridge";
    };
  };

  boot.kernel.sysctl = {
    "vm.max_map_count" = lib.mkForce 1048576;
    # VPP does the forwarding, not Linux
    "net.ipv4.ip_forward" = lib.mkForce false;
    "net.ipv6.conf.all.forwarding" = lib.mkForce false;
  };

  # dnsmasq needs VPP up first (for tap0)
  systemd.services.dnsmasq.requires = ["vpp.service"];
  systemd.services.dnsmasq.after = ["vpp.service"];

  # Thunderbolt NICs - added after VPP starts (Thunderbolt takes time to enumerate)
  # This service is best-effort: Thunderbolt PCIe tunnels can fail, so we don't fail the service
  # systemd.services.vpp-thunderbolt = {
  #   description = "Add Thunderbolt NICs to VPP";
  #   after = ["vpp.service"];
  #   requires = ["vpp.service"];
  #   wantedBy = ["multi-user.target"];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #   };
  #   path = [pkgs.vpp pkgs.iproute2];
  #   script = ''
  #     set +e  # Don't fail on errors - Thunderbolt is best-effort

  #     # Wait for VPP to be ready first
  #     for i in $(seq 1 30); do
  #       if vppctl show version >/dev/null 2>&1; then
  #         echo "VPP ready"
  #         break
  #       fi
  #       sleep 1
  #     done

  #     # Wait longer for Thunderbolt - PCIe tunnels take time to establish
  #     # Thunderbolt NICs may not be available if tunnel activation failed
  #     sleep 5

  #     added=0
  #     ${lib.concatMapStringsSep "\n" (port: ''
  #         # Wait for this interface (up to 60 seconds)
  #         found=0
  #         for i in $(seq 1 60); do
  #           if ip link show ${port.linux} >/dev/null 2>&1; then
  #             echo "${port.linux} found"
  #             found=1
  #             break
  #           fi
  #           if [ $i -eq 1 ] || [ $((i % 10)) -eq 0 ]; then
  #             echo "Waiting for ${port.linux}... $i"
  #           fi
  #           sleep 1
  #         done

  #         if [ $found -eq 1 ]; then
  #           # Try to bring up the interface - may fail if Thunderbolt tunnel is broken
  #           if ip link set ${port.linux} up 2>&1; then
  #             echo "${port.linux} up"
  #             # Add to VPP
  #             if vppctl create interface rdma host-if ${port.linux} name ${port.name} 2>&1; then
  #               vppctl set interface mac address ${port.name} ${port.mac} 2>&1 || true
  #               vppctl set interface l2 bridge ${port.name} 1 2>&1 || true
  #               vppctl set interface state ${port.name} up 2>&1 || true
  #               echo "Added ${port.name} to VPP bridge"
  #               added=$((added + 1))
  #             else
  #               echo "Warning: Failed to create RDMA interface for ${port.linux}"
  #             fi
  #           else
  #             echo "Warning: Cannot bring up ${port.linux} (Thunderbolt tunnel may have failed)"
  #           fi
  #         else
  #           echo "Warning: ${port.linux} not found after 60s (Thunderbolt device may not be connected)"
  #         fi
  #       '')
  #       thunderboltPorts}

  #     echo "Thunderbolt setup complete: $added interfaces added"
  #     vppctl show interface | grep -E "^tb" || echo "No Thunderbolt interfaces in VPP"
  #     exit 0  # Always succeed - Thunderbolt is optional
  #   '';
  # };

  # DHCPv6-PD setup via API (CLI commands don't work on RDMA interfaces)
  # systemd.services.vpp-dhcp6-pd = {
  #   description = "Configure VPP DHCPv6 Prefix Delegation";
  #   after = ["vpp.service"];
  #   requires = ["vpp.service"];
  #   wantedBy = ["multi-user.target"];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #   };
  #   path = [pkgs.vpp];
  #   script = ''
  #     # Wait for VPP to be ready and WAN interface to be up
  #     for i in $(seq 1 60); do
  #       if vppctl show interface wan0 2>/dev/null | grep -q "up"; then
  #         echo "VPP and WAN interface ready"
  #         break
  #       fi
  #       echo "Waiting for VPP wan0... $i"
  #       sleep 1
  #     done

  #     # Additional delay to ensure VPP is fully initialized
  #     sleep 5

  #     # Enable DHCPv6 client subsystem (required before PD)
  #     # Retry up to 5 times if it fails
  #     for attempt in $(seq 1 5); do
  #       result=$(vat2 dhcp6_clients_enable_disable '{"enable": true}' 2>&1)
  #       if echo "$result" | grep -q '"retval".*0'; then
  #         echo "DHCPv6 clients enabled"
  #         break
  #       fi
  #       echo "Attempt $attempt: dhcp6_clients_enable_disable failed, retrying..."
  #       sleep 2
  #     done

  #     # Enable DHCPv6 client on WAN (sw_if_index 1)
  #     for attempt in $(seq 1 5); do
  #       result=$(vat2 dhcp6_client_enable_disable '{"sw_if_index": 1, "enable": true}' 2>&1)
  #       if echo "$result" | grep -q '"retval".*0'; then
  #         echo "DHCPv6 client enabled on WAN"
  #         break
  #       fi
  #       echo "Attempt $attempt: dhcp6_client_enable_disable failed, retrying..."
  #       sleep 2
  #     done

  #     # Enable DHCPv6-PD client with prefix group "hgw"
  #     for attempt in $(seq 1 5); do
  #       result=$(vat2 dhcp6_pd_client_enable_disable '{"sw_if_index": 1, "prefix_group": "hgw", "enable": true}' 2>&1)
  #       if echo "$result" | grep -q '"retval".*0'; then
  #         echo "DHCPv6-PD client enabled"
  #         break
  #       fi
  #       echo "Attempt $attempt: dhcp6_pd_client_enable_disable failed, retrying..."
  #       sleep 2
  #     done

  #     # Wait for prefix delegation from ISP
  #     for i in $(seq 1 30); do
  #       if vppctl show ip6 prefixes 2>/dev/null | grep -q "prefix group: hgw"; then
  #         echo "Received delegated prefix"
  #         break
  #       fi
  #       echo "Waiting for DHCPv6-PD... $i"
  #       sleep 1
  #     done

  #     # Assign /64 from delegated prefix to LAN (bvi1 = sw_if_index 8)
  #     vppctl set ip6 address bvi1 prefix group hgw ::1/64

  #     # Get the delegated prefix and add it to Router Advertisements
  #     # so LAN clients (including Linux tap0) get public IPv6 addresses
  #     PREFIX=$(vppctl show ip6 prefixes | grep -oP '2[0-9a-f:]+::/\d+' | head -1)
  #     if [ -n "$PREFIX" ]; then
  #       # Extract just the network part (e.g., 2a02:168:58b4::) for /64
  #       PREFIX_BASE=$(echo "$PREFIX" | sed 's|/[0-9]*||')
  #       # For a /48 delegated prefix, we use the first /64
  #       vppctl ip6 nd bvi1 prefix ''${PREFIX_BASE}/64 3000 2000
  #       echo "Added prefix ''${PREFIX_BASE}/64 to Router Advertisements"
  #     fi

  #     echo "DHCPv6-PD configured successfully"
  #     vppctl show ip6 prefixes
  #     vppctl show interface address bvi1
  #   '';
  # };

  # Debug script for VPP diagnostics
  environment.systemPackages = lib.mkAfter [
    (pkgs.writeShellScriptBin "vpp-debug" ''
      #!/usr/bin/env bash
      OUT="/root/vpp-debug-$(date +%Y%m%d-%H%M%S).txt"
      VPPCTL="${pkgs.vpp}/bin/vppctl"

      echo "=== VPP Debug Info $(date) ===" > "$OUT"

      echo -e "\n=== show version ===" >> "$OUT"
      $VPPCTL show version >> "$OUT" 2>&1

      echo -e "\n=== show interface ===" >> "$OUT"
      $VPPCTL show interface >> "$OUT" 2>&1

      echo -e "\n=== show interface address ===" >> "$OUT"
      $VPPCTL show interface address >> "$OUT" 2>&1

      echo -e "\n=== show bridge-domain 1 detail ===" >> "$OUT"
      $VPPCTL show bridge-domain 1 detail >> "$OUT" 2>&1

      echo -e "\n=== show l2fib all ===" >> "$OUT"
      $VPPCTL show l2fib all >> "$OUT" 2>&1

      echo -e "\n=== show ip fib ===" >> "$OUT"
      $VPPCTL show ip fib >> "$OUT" 2>&1

      echo -e "\n=== show ip neighbors ===" >> "$OUT"
      $VPPCTL show ip neighbors >> "$OUT" 2>&1

      echo -e "\n=== show nat44 addresses ===" >> "$OUT"
      $VPPCTL show nat44 addresses >> "$OUT" 2>&1

      echo -e "\n=== show nat44 interfaces ===" >> "$OUT"
      $VPPCTL show nat44 interfaces >> "$OUT" 2>&1

      echo -e "\n=== show nat44 static mappings ===" >> "$OUT"
      $VPPCTL show nat44 static mappings >> "$OUT" 2>&1

      echo -e "\n=== show errors ===" >> "$OUT"
      $VPPCTL show errors >> "$OUT" 2>&1

      echo -e "\n=== show buffers ===" >> "$OUT"
      $VPPCTL show buffers >> "$OUT" 2>&1

      echo -e "\n=== show memory main-heap ===" >> "$OUT"
      $VPPCTL show memory main-heap >> "$OUT" 2>&1

      echo -e "\n=== show hardware-interfaces ===" >> "$OUT"
      $VPPCTL show hardware-interfaces >> "$OUT" 2>&1

      echo -e "\n=== show dhcp client ===" >> "$OUT"
      $VPPCTL show dhcp client >> "$OUT" 2>&1

      # Enable tracing and capture some packets
      echo -e "\n=== Enabling trace (virtio-input 100, rdma-input 100) ===" >> "$OUT"
      $VPPCTL clear trace >> "$OUT" 2>&1
      $VPPCTL trace add virtio-input 100 >> "$OUT" 2>&1
      $VPPCTL trace add rdma-input 100 >> "$OUT" 2>&1

      echo "Waiting 5 seconds for traffic..." >> "$OUT"
      sleep 5

      echo -e "\n=== show trace ===" >> "$OUT"
      $VPPCTL show trace >> "$OUT" 2>&1

      echo -e "\n=== Linux: ip addr ===" >> "$OUT"
      ip addr >> "$OUT" 2>&1

      echo -e "\n=== Linux: ip route ===" >> "$OUT"
      ip route >> "$OUT" 2>&1

      echo -e "\n=== Linux: ping -c2 192.168.23.1 ===" >> "$OUT"
      ping -c2 192.168.23.1 >> "$OUT" 2>&1

      echo -e "\n=== Linux: ping -c2 1.1.1.1 ===" >> "$OUT"
      ping -c2 1.1.1.1 >> "$OUT" 2>&1

      echo -e "\n=== show trace (after pings) ===" >> "$OUT"
      $VPPCTL show trace >> "$OUT" 2>&1

      echo -e "\n=== show errors (after pings) ===" >> "$OUT"
      $VPPCTL show errors >> "$OUT" 2>&1

      echo -e "\n=== journalctl -u vpp (last 50 lines) ===" >> "$OUT"
      journalctl -u vpp --no-pager -n 50 >> "$OUT" 2>&1

      echo ""
      echo "Debug info written to: $OUT"
    '')
  ];

  services = {
    vpp = {
      enable = true;
      group = "vpp";

      settings = {
        logging = {
          default-log-level = "info";
          default-syslog-log-level = "info";
        };

        buffers = {
          "default data-size" = 2048;
          buffers-per-numa = 131072;
          page-size = "2M";
        };

        cpu = {
          main-core = 2;
          corelist-workers = "3-7";
        };

        dpdk = {
          # Use 1GB hugepages mount
          # huge-dir = "/dev/hugepages-1G";
          dev = {
            default = {
              num-rx-queues = 4;
              num-tx-queues = 4;
              num-rx-desc = 4096;
              num-tx-desc = 4096;
            };
            # default.socket-mem = 4096;
            "0000:01:00.0".name = "wan0";
            "0000:01:00.1".name = "lan0";
          };
        };

        # ip = {
        #   heap-size = "64M";
        # };

        ip6 = {
          heap-size = "64M";
          hash-buckets = 131072;
        };

        plugins.plugin = {
          # DPDK for Mellanox (mlx5 PMD), AF_XDP for Intel
          # Don't enable rdma_plugin - conflicts with dpdk mlx5 PMD
          "rdma_plugin.so".disable = true;
          "af_xdp_plugin.so".enable = true;
          "dpdk_plugin.so".enable = true;

          # Disable broken plugin (undefined symbol: vxlan6_gpe_rewrite)
          "ioam_plugin.so".disable = true;

          # Disable WireGuard - not needed, kernel handles it
          # This prevents wg6-output-tun-handoff congestion drops
          "wireguard_plugin.so".disable = true;

          # Core functionality
          "nat_plugin.so".enable = true;
          "ping_plugin.so".enable = true;
          "dhcp_plugin.so".enable = true;

          # Monitoring
          # "prom_plugin.so".enable = true;
          # "http_static_plugin.so".enable = true;
        };
      };
      startupConfig = ''
        set interface mac address ${lan.name} ${lan.mac}
        set interface mac address ${wan.name} ${wan.mac}
        set interface mtu packet 1500 ${wan.name}

        set dhcp client intfc ${wan.name} hostname router
        set interface state ${wan.name} up

        create bridge-domain 1 learn 1 forward 1 uu-flood 1 flood 1 arp-term 0

        bvi create instance 1
        set int mac address bvi1 50:6b:4b:03:04:cc
        set int l2 bridge bvi1 1 bvi
        set int ip address bvi1 192.168.23.1/24
        set int state bvi1 up

        set interface l2 bridge ${lan.name} 1
        set interface state ${lan.name} up

        create tap host-if-name ${network.host.tap} num-rx-queues 4 num-tx-queues 4 rx-ring-size 16384 tx-ring-size 16384 host-mtu-size 9000 gso gro-coalesce
        set interface l2 bridge ${network.host.tap} 1
        set interface state ${network.host.tap} up

        nat44 forwarding enable
        nat44 plugin enable sessions 131072
        nat44 add interface address ${wan.name}
        set interface nat44 in bvi1 out ${wan.name}

        set int ip6 table ${wan.name} 0
        ip6 nd address autoconfig ${wan.name} default-route
        dhcp6 client ${wan.name}
        dhcp6 pd client ${wan.name} prefix group hgw
        set ip6 address bvi1 prefix group hgw ::1/64
        ip6 nd address autoconfig bvi1 default-route
        ip6 nd bvi1 ra-managed-config-flag ra-other-config-flag ra-interval 30 20 ra-lifetime 180

        # hairpin rules
        ${toVppHairpinRules network.lan.addr portForwardHosts.router}

        # Port forwarding rules
        ${toVppNatRules wan.name portForwardHosts}
      '';

      # startupConfig = ''
      #   # Set hardware MAC addresses (VPP generates random MACs otherwise)
      #   # WAN MAC is set by DPDK, LAN needs manual setting
      #   set interface mac address ${lan.name} ${lan.mac}

      #   # WAN setup - DHCP (IPv4) and SLAAC (IPv6)
      #   # DHCPv6-PD is configured via vpp-dhcp6-pd.service (CLI commands don't work reliably)
      #   set interface mtu packet 1500 ${wan.name}
      #   set interface state ${wan.name} up
      #   set dhcp client intfc ${wan.name} hostname router
      #   ip6 nd address autoconfig ${wan.name} default-route

      #   # Create bridge domain for LAN (bridges physical LAN + TAP to Linux)
      #   # arp-term 1: VPP answers ARP from its neighbor table (more reliable than flooding via tap0)
      #   create bridge-domain 1 # learn 1 forward 1 uu-flood 1 flood 1 arp-term 1

      #   # Add physical LAN (Mellanox) to bridge
      #   set interface l2 bridge ${lan.name} 1
      #   set interface state ${lan.name} up

      #   # Thunderbolt Mellanox ports are added by vpp-thunderbolt.service after enumeration

      #   # Create TAP for host services and add to bridge (jumbo MTU, large ring sizes for throughput)
      #   # Note: num-tx-queues must match what kernel expects (4 on this system)
      #   create tap host-if-name ${network.host.interface} host-ip4-addr ${network.host.addr}/${toString network.host.prefix} host-ip4-gw ${network.lan.addr} num-rx-queues 4 num-tx-queues 4 rx-ring-size 16384 tx-ring-size 16384 host-mtu-size 9000 gso gro-coalesce
      #   set interface l2 bridge ${network.host.interface} 1
      #   set interface state ${network.host.interface} up

      #   # Create BVI (Bridge Virtual Interface) - this is the LAN gateway
      #   # Use a vendor MAC (Mellanox-like) instead of locally-administered MAC
      #   # to avoid filtering by Mikrotik switches
      #   bvi create instance 1
      #   set interface mac address bvi1 50:6b:4b:03:04:cc
      #   set interface l2 bridge bvi1 1 bvi
      #   set interface ip address bvi1 ${network.lan.addr}/${toString network.lan.prefix}
      #   set interface ip address bvi1 fdde:ad::1/64
      #   set interface state bvi1 up

      #   # IPv6 Router Advertisements for LAN (ULA prefix; global prefix added by vpp-dhcp6-pd.service)
      #   ip6 nd bvi1 ra-interval 30 60 ra-lifetime 180
      #   ip6 nd bvi1 prefix fdde:ad::/64 86400 14400

      #   # NAT44 setup - NAT on the BVI (LAN gateway)
      #   nat44 forwarding enable
      #   nat44 plugin enable sessions 131072
      #   nat44 add interface address ${wan.name}
      #   set interface nat44 in bvi1 out ${wan.name}
      #   # WAN also needs 'in' for DNAT (port forwarding from WAN)
      #   set interface nat44 in ${wan.name}

      #   # LAN hairpin NAT: redirect .1 ports to Linux (.254) for local services
      #   ${toVppHairpinRules network.lan.addr portForwardHosts.router}

      #   # Port forwarding rules
      #   ${toVppNatRules wan.name portForwardHosts}
      # '';
    };
  };
}
