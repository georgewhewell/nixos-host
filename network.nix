lib: rec {
  domains = {
    lan = "lan.satanic.link";
    public = "satanic.link";
  };

  # Each VLAN owns its subnet prefix and DHCP scope. id=null means untagged.
  # `prefix` is the first three octets; helpers append the host octet.
  vlans = {
    lan = {
      id = null;
      # The flat LAN remains untagged until its ports are inventoried.  The
      # production router-on-a-stick design moves it to VLAN 10; keeping that
      # target separate avoids changing the live broadcast domain merely by
      # evaluating the staged VPP configuration.
      targetId = 10;
      prefix = "192.168.23";
      cidr = 24;
      mtu = 9000;
      gatewayHost = 1;
      dhcp = {
        start = 32;
        end = 249;
        lease = "6h";
      };
      role = "trusted";
    };
    # High-speed MLX5/BlueField fabric. Hosts use the CRS812 SVI as their
    # gateway; traffic within the subnet stays in the Marvell switch ASIC.
    fabric = {
      id = 25;
      prefix = "192.168.25";
      cidr = 24;
      mtu = 9000;
      gatewayHost = 1;
      role = "trusted";
    };
    # Second host-facing CX5 rail. This is another IPv4 subnet on the existing
    # untagged fabric VLAN-25 L2 domain, not an 802.1Q VLAN 26.
    fabric2 = {
      id = null;
      prefix = "192.168.26";
      cidr = 24;
      mtu = 9000;
      role = "trusted";
    };
    # Reserved test subnet for the CX5 SharedIO VFs. MULTI_PORT_VHCA_EN gives
    # both VFs carrier, but this firmware does not forward frames between host
    # controllers, so production traffic uses the physical fabric instead.
    cx5Peer = {
      id = null;
      prefix = "192.168.27";
      cidr = 30;
      mtu = 9000;
      role = "transit";
    };
    # Optional PCIe host-PF transit between the router and BlueField. This is
    # deliberately a separate /30: it is never the LAN, DNS/DHCP, or default
    # route, and it can disappear without affecting either machine's boot.
    bluefieldHostPf = {
      id = null;
      prefix = "192.168.28";
      cidr = 30;
      mtu = 9000;
      role = "transit";
    };
    iot = {
      id = 20;
      prefix = "192.168.20";
      cidr = 24;
      gatewayHost = 1;
      dhcp = {
        start = 32;
        end = 249;
        lease = "6h";
      };
      role = "iot";
    };
    guest = {
      id = 30;
      prefix = "192.168.30";
      cidr = 24;
      gatewayHost = 1;
      dhcp = {
        start = 32;
        end = 249;
        lease = "6h";
      };
      role = "guest";
    };
    mgmt = {
      id = 40;
      prefix = "192.168.40";
      cidr = 24;
      gatewayHost = 1;
      dhcp = {
        start = 32;
        end = 249;
        lease = "6h";
      };
      role = "mgmt";
    };
    wifi = {
      id = 50;
      prefix = "192.168.50";
      cidr = 24;
      gatewayHost = 1;
      dhcp = {
        start = 32;
        end = 249;
        lease = "6h";
      };
      role = "trusted";
    };
    # not 802.1Q but lives in the same model so consumers can iterate uniformly
    wireguard = {
      id = null;
      prefix = "192.168.24";
      cidr = 24;
      gatewayHost = 1;
      role = "vpn";
    };
    # Control-plane rescue subnet, reached from abroad through `rescueTunnel`.
    #
    # NOT an 802.1Q VLAN. Like fabric2 above, this is a second IPv4 network on
    # the existing untagged LAN L2, so it needs no switch configuration and
    # cannot be broken by one -- which matters for something whose entire job
    # is to work on the day other things do not.
    #
    # Two reasons it exists rather than reusing 192.168.23.0/24:
    #   1. ax102's wg-hydra-bld already claims .7, .8, .24, .136, .192 and .247
    #      as /32s. WireGuard routes by longest prefix, so routing the LAN /24
    #      down the rescue tunnel would still send those hosts into the Hydra
    #      tunnel -- which is dialled out over the very WAN that is down when
    #      the rescue tunnel is needed.
    #   2. A host reached at 192.168.102.X replies to k3 at 192.168.102.19
    #      ON-LINK. No gateway is consulted, so the path works precisely when
    #      the gateway is the casualty.
    #
    # Only a handful of hosts carry an address here, by design: this is a
    # control plane, not a second LAN. Anything without one is reached by
    # hopping through k3.
    rescue = {
      id = null;
      prefix = "192.168.102";
      cidr = 24;
      # These addresses ride existing LAN interfaces, so the real MTU is
      # whatever that interface has. Recorded as the tunnel path's MTU, which
      # is what actually constrains a rescue flow; k3 clamps TCP MSS to match.
      mtu = 1500;
      gatewayHost = 19; # k3
      role = "mgmt";
    };
    # Control-only backup-WAN transit between rock-5b and the BlueField VPP
    # router. The CRS812 carries this tag only between their two ports once
    # bridge VLAN filtering is enabled.
    wanBackup = {
      id = 101;
      prefix = "192.168.101";
      # One transit VLAN, multiple replaceable edge uplinks: Rock's USB
      # tether, BlueField's router port, and k3's WiFi tether. A /29 avoids
      # inventing a second hardcoded point-to-point network for each handset.
      cidr = 29;
      mtu = 1500;
      role = "transit";
    };
  };

  policies.backupWan = {
    # Explicit identities, not a LAN subnet: arr-servers/qBittorrent (.15) is
    # deliberately absent and therefore cannot use the phone on any port.
    allowedSourceHosts = [
      "router"
      "fuckup"
      "trex"
      "mbp"
      "mikrotik-crs812"
      "bluefield2"
    ];
    # The VPP lab's trusted peer lets us prove the complete Trex -> VPP ->
    # Rock -> iPhone path before production VLANs replace documentation nets.
    additionalSourceCidrs = [
      "198.18.10.2/32"
      # The "router" entry above resolves to .1, which the BlueField took at
      # the gateway cutover. The old router is now an ordinary service host at
      # .31 -- and it is the one running DNS, DHCP, Home Assistant and
      # ESPHome. Without this line the single most important machine to be
      # able to reach is the single machine the backup WAN refuses.
      "${controlPlaneIp}/32"
    ];
    vppTestReturnCidrs = ["198.18.10.0/24"];
    tcpPorts = [22 53 80 443 853];
    # 51823 is the rescue tunnel (see `rescue` below). It must be listed here
    # because k3's own OUTPUT chain is filtered against this same set: without
    # it the tunnel comes up over the main WAN and then goes silent the moment
    # the phone becomes the only egress -- exactly when it is needed.
    udpPorts = [53 123 443 35947 51820 51821 51823];
  };

  # Out-of-band rescue tunnel. Every existing way into this network depends on
  # the ISP link, the BlueField gateway at .1, and the .31 service host all
  # being alive at once; the backup WAN is egress-only and cannot help, because
  # a phone hotspot is CGNAT and accepts no inbound flow. So k3 dials OUT to a
  # public rendezvous and holds the tunnel open with a keepalive. Arriving is
  # then ax102's problem, not the ISP's.
  #
  # This is a control path, not a WAN: it carries policies.backupWan's port set
  # into the `rescue` subnet above, and nothing else. Named `rescueTunnel` to
  # keep it distinct from `vlans.rescue`, which is the subnet it delivers to.
  rescueTunnel = {
    interface = "wg-rescue";
    subnet = "10.102.0.0/24";
    # Distinct from the Hydra builders' 51822 on the same box.
    listenPort = 51823;
    # Pinned via the LAN gateway so the health check always tests the *main*
    # path, whatever the default route currently says. Deliberately not one of
    # dnsmasq's upstreams below: a probe target that doubles as a resolver
    # stops being a probe the moment you need it.
    healthProbeTarget = "1.0.0.1";
    # A stale tunnel is indistinguishable from a dead one from abroad, so the
    # health timer rebuilds the interface if no handshake lands within this.
    handshakeStaleSeconds = 300;
    ax102 = {
      wg = "10.102.0.1";
      endpoint = "213.239.212.173:51823";
      publicKey = "ncesw5s/Xd9OwkxEv7BIr+5YgwHTgFeJdEbP0CfUx3w=";
    };
    k3 = {
      wg = "10.102.0.2";
      publicKey = "0HqBnv5eTB2MmEicuXO0qF9tmEigGdYT3nVVEkPH4XY=";
    };
    # Upstream resolvers for k3's standby DNS. Plain 53, because 853/DoH would
    # add a dependency on the very thing that is broken when this matters.
    resolvers = ["1.1.1.1" "9.9.9.9"];
  };

  benchmarkBuildHosts = let
    strixHaloRunner = {
      gpus = [
        {
          type = "amd";
          arch = "1151";
        }
      ];
      npus = [
        {
          type = "amd";
          arch = "xdna2";
        }
      ];
    };
    strixHaloSystemFeatures = [
      "gccarch-znver5"
      "rocm"
      "benchmark"
      "kvm"
      "nixos-test"
    ];
  in {
    strix-1 =
      strixHaloRunner
      // {
        ipv4 = "192.168.23.136";
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC3yLn8cnBVB/cJCdTP0AdkPjTkpHmXiP0s+xHPWZ+mq";
        maxJobs = 1;
        speedFactor = 32;
        systems = ["x86_64-linux"];
        systemFeatures = strixHaloSystemFeatures;
      };
    strix-2 =
      strixHaloRunner
      // {
        ipv4 = "192.168.23.192";
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID0RsY9sp58nDjojVM9uAZ+6DoLxi/8LrGuonSoSC2DS";
        maxJobs = 1;
        speedFactor = 32;
        systems = ["x86_64-linux"];
        systemFeatures = strixHaloSystemFeatures;
      };
    mbp = {
      ipv4 = "192.168.23.24";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEn8GwjuFsx8r3wXq0J28mHg2WZdbo4NH45bxg9EwSTO";
      maxJobs = 1;
      speedFactor = 64;
      systems = ["aarch64-darwin"];
      systemFeatures = ["apple-virt" "benchmark" "big-parallel" "apple-m4" "metal"];
      gpus = [];
    };
    goblin = {
      ipv4 = primaryIp hosts.goblin;
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDRJYI4x/nKcftcIo6pmy9gRR0NznkFUQ3eliggcGY9N";
      maxJobs = 1;
      speedFactor = 96;
      systems = ["aarch64-darwin"];
      systemFeatures = ["apple-virt" "benchmark" "big-parallel" "apple-m4" "metal"];
      gpus = [];
    };
  };

  hydraBuilders = {
    interface = "wg-hydra-bld";
    subnet = "10.101.0.0/24";
    ax102 = {
      wg = "10.101.0.2";
      endpoint = "213.239.212.173:51822";
      publicKey = "Y+jK3Cf2xVYvaYRy41MfKqINJarEdhBIlqWgFbCfF1U=";
    };
    router = {
      wg = "10.101.0.1";
    };
    builders = {
      rock-5b = {
        ipv4 = primaryIp hosts."rock-5b";
      };
      trex = {
        ipv4 = "192.168.23.8";
      };
      fuckup = {
        ipv4 = primaryIp hosts.fuckup;
      };
      strix-1 = {
        ipv4 = benchmarkBuildHosts.strix-1.ipv4;
      };
      strix-2 = {
        ipv4 = benchmarkBuildHosts.strix-2.ipv4;
      };
      mbp = {
        ipv4 = benchmarkBuildHosts.mbp.ipv4;
      };
      goblin = {
        ipv4 = benchmarkBuildHosts.goblin.ipv4;
      };
    };
  };

  # A host can sit on multiple VLANs (e.g. the router on every one as gateway).
  # `addresses` maps vlan name -> host octet within that vlan's prefix.
  # `mac` is optional. `extraNames` are additional DNS aliases that resolve to the
  # host's primary IP (the lan address if present, else the first vlan listed).
  hosts = {
    router = {
      addresses = {
        lan = 1;
        cx5Peer = 1;
        iot = 1;
        guest = 1;
        mgmt = 1;
        wifi = 1;
        # The rescue octet is 31, not 1: since the VPP cutover this machine
        # holds only .31 on the LAN (.1 moved to bluefield2-vpp-lan), and it
        # is the host running DNS, DHCP, Home Assistant and ESPHome -- the
        # single most valuable thing to be able to reach from abroad.
        rescue = 31;
      };
      extraNames = ["frigate"];
    };
    # Spotifyd runs in a WiFi-only macvlan namespace on the router. Keep its
    # address below the dynamic pool so libmdns sees and advertises exactly one
    # client-reachable address instead of the router's host-PF/RShim links.
    spotifyd = {
      mac = "02:50:00:00:00:30";
      addresses = {wifi = 30;};
    };
    # CRS210-8G-2S+. Named for the board like the other switches; the old
    # link-speed name stays as an alias so existing references keep resolving.
    "mikrotik-crs210" = {
      mac = "e4:8d:8c:a8:de:40";
      addresses = {lan = 2;};
      extraNames = ["mikrotik-10g"];
    };
    "unifi-ac-pro" = {
      mac = "80:2a:a8:80:96:ef";
      addresses = {lan = 3;};
      extraNames = ["ap"];
    };
    "x10-ipmi" = {
      mac = "0c:c4:7a:89:fb:37";
      addresses = {lan = 4;};
    };
    nixhost = {
      mac = "0c:c4:7a:87:b9:d8";
      addresses = {lan = 5;};
    };
    vacuum = {
      mac = "78:11:dc:ec:86:ea";
      # Moved to the wifi VLAN when the SSID migrated, so the old untagged-LAN
      # reservation stopped applying and it ran on a pool lease (.187), which
      # is what made it hard to find. Host octet 6 is below the VLAN 50 pool
      # (32-249), so it is a reservation rather than a contended address.
      addresses = {wifi = 6;};
    };
    fuckup = {
      mac = "b8:6f:35:ab:31:89";
      addresses = {
        lan = 7;
        rescue = 7;
      };
    };
    trex = {
      mac = "50:6b:4b:03:04:cb";
      # mlxlan0 (100G Mellanox PF) historically grabbed a dynamic lease as a
      # standalone DHCP client before OVS enslaved it, registering trex -> a pool
      # address and shadowing the static .8 in DNS. Reserve its MAC to .8 too so
      # any stray lease resolves to the correct host instead of a dynamic IP.
      extraMacs = ["50:6b:4b:0d:24:86"];
      # The CRS804 cage-4 25G access uplink extends the untagged LAN broadcast
      # domain into fabric VLAN 25. Keep both subnets on the same OVS internal
      # port so Trex reaches the Strix fabric through ASIC switching instead
      # of routing through the CRS804 CPU and the main router.
      addresses = {
        lan = 8;
        fabric = 8;
        rescue = 8;
      };
      extraNames = ["jellyfin" "grafana" "home" "radarr" "sonarr" "autobrr" "cache" "kimi" "dsh" "opencode"];
    };
    # Trex's RoCE endpoint: a ConnectX-4 SR-IOV VF in the host namespace
    # (mlxlan0v1 / mlx5_1). The OVS internal port ovs-host cannot serve RDMA
    # because it is a software port with no verbs device, so RDMA consumers
    # (SPDK NVMe-oF target, NFS/BeeGFS over RDMA) bind this address instead.
    # Traffic leaves via the VF's switchdev representor into the ovs-mlx bridge.
    # MAC last octet 0xd0 == 208 to mirror the host octet.
    "trex-rdma" = {
      # Now simply a second fabric address on trex's ConnectX-4 PF, not an
      # SR-IOV VF (2026-08-08 -- switchdev/OVS removed). Kept as a distinct
      # host record so every client's NVMe-oF target address is unchanged.
      mac = "50:6b:4b:0d:24:86";
      addresses = {fabric = 208;};
    };
    # fuckup's RoCE endpoint: VF 0 on the live ConnectX-4 Lx port. The PF
    # remains a br0.lan slave for the workstation's LAN traffic, while this
    # VF stays standalone so it retains a real mlx5 verbs device and can own
    # the fabric address directly.
    "fuckup-rdma" = {
      mac = "52:6f:35:ab:31:cf";
      addresses = {fabric = 207;};
    };
    # Windows build VM on fuckup (machines/x86/fuckup/windows-vm.nix), on
    # ConnectX VF 1 via macvtap. MAC carried over from its libvirt life on
    # trex. The IP is also set statically inside Windows. Replacing `lan` with
    # a `builders` address moves the VF onto that VLAN (fabric-rdma-vf.nix),
    # once the gateway, switches and VPP ACLs carry it.
    windows = {
      mac = "52:54:00:f7:90:e7";
      addresses = {lan = 6;};
      # NixOS-WSL (machines/wsl/windows) sits behind WSL2's NAT. Its sshd
      # listens on innerPort, which wslrelay mirrors to Windows' loopback; a
      # wildcard portproxy publishes that as port. They differ because the
      # portproxy cannot share a port with wslrelay's loopback listener, and
      # a proxy pinned to the LAN address loses a boot race with the address.
      wslSsh = {
        port = 2222;
        innerPort = 2223;
      };
    };
    # CRS510-8XS-2XQ. Same board-name convention; old alias retained.
    "mikrotik-crs510" = {
      mac = "48:a9:8a:93:42:4c";
      addresses = {lan = 9;};
      extraNames = ["mikrotik-100g"];
    };
    "mikrotik-crs812" = {
      mac = "38:32:7a:14:ff:67";
      addresses = {
        lan = 27;
        fabric = 1;
      };
      # Preserve the old CRS804 DNS name while clients migrate.
      extraNames = ["mikrotik-400g"];
    };
    # Reconnected 2026-08-15. It came back still holding .23.27/.25.1, which
    # the CRS812 had taken over, so both switches were claiming the same two
    # addresses on the fabric L2 domain. Renumbered here and in
    # machines/routeros/crs804/config.rsc; the CRS812 keeps the gateway.
    "mikrotik-crs804" = {
      mac = "d0:ea:11:d1:9d:85";
      addresses = {
        lan = 28;
        fabric = 2;
      };
    };
    trx90bmc = {
      mac = "9c:6b:00:57:31:77";
      addresses = {lan = 10;};
    };
    "apc-ups" = {
      mac = "28:29:86:8b:3f:cb";
      addresses = {lan = 11;};
      extraNames = ["apc8b3fcb"];
    };
    printer = {
      mac = "b4:22:00:cf:18:63";
      addresses = {lan = 12;};
    };
    cerberus = {
      mac = "c8:f0:9e:de:3c:2f";
      addresses = {lan = 13;};
    };
    n100 = {
      mac = "9c:6b:00:39:f3:91";
      addresses = {
        lan = 14;
        fabric = 14;
        cx5Peer = 2;
      };
    };
    "arr-servers" = {
      mac = "9e:9c:05:57:e8:11";
      addresses = {lan = 15;};
    };
    "zigbee-stick" = {
      mac = "1c:69:20:a1:d7:9f";
      addresses = {lan = 16;};
    };
    nanokvm = {
      # eth0. Locally-administered MAC pinned in the machine config
      # (the SG2002 GMAC has no fused address); Colmena deploys over
      # this interface.
      mac = "02:4b:56:4d:00:17";
      addresses = {lan = 17;};
    };
    licheerv = {
      # LicheeRV-Nano-W (SG2002) on trex's USB port: USB fastboot boot,
      # NFS root from trex. Same no-fused-MAC
      # situation as nanokvm; pinned locally-administered "LRV" + .29
      # in the machine config. WiFi stays off — its AIC8800 ships the
      # same burned-in default MAC as nanokvm's (38:7a:cc:40:41:e3),
      # so both on the wifi VLAN would collide.
      mac = "02:4c:52:56:00:29";
      addresses = {lan = 29;};
    };
    "rock-5b" = {
      mac = "00:e0:4c:68:02:e7";
      addresses = {
        lan = 18;
        wanBackup = 1;
      };
    };
    k3 = {
      mac = "50:0a:52:0b:e5:6f";
      extraMacs = [
        "50:0a:52:0b:81:20"
      ];
      addresses = {
        lan = 19;
        wanBackup = 3;
        # k3 is the rescue subnet's gateway and the only host forwarding it.
        rescue = 19;
      };
    };
    mbp = {
      mac = "c2:c5:7f:8c:7a:51";
      # mbp's LAN link is now the 2.5GbE Thunderbolt/USB ethernet (en11); reserve
      # .24 to its MAC too so `mbp` resolves to a stable address it actually holds
      # (bare `mbp` was a dead static record while it pulled a dynamic pool lease).
      extraMacs = [
        "88:c9:b3:b3:2a:da"
        "24:5e:be:81:84:16"
      ];
      addresses = {lan = 24;};
    };
    goblin = {
      mac = "1c:1d:d3:e9:2b:31";
      # Match the DHCP ID even when macOS rotates its private Wi-Fi MAC.
      dhcpClientId = "goblin";
      addresses = {wifi = 247;};
    };
    goblin-ethernet = {
      mac = "1c:1d:d3:eb:67:55";
      addresses = {lan = 247;};
    };
    "10g-onti" = {
      mac = "d0:aa:5f:01:45:a8";
      addresses = {lan = 20;};
    };
    "gh-runner-grw" = {addresses = {lan = 50;};};
    "10g-poe" = {
      mac = "00:23:79:00:57:90";
      addresses = {lan = 21;};
    };
    bluefield2 = {
      mac = "b8:ce:f6:f8:d7:b0";
      addresses = {
        lan = 22;
        fabric = 22;
        wanBackup = 2;
        rescue = 22;
      };
    };
    # VPP's data-plane PF is distinct from BlueField Linux management. This
    # temporary untagged address reaches k3 through its present switch path;
    # remove it after k3 is moved onto the VLAN-aware CRS fabric.
    "bluefield2-vpp-lan" = {
      mac = "b8:ce:f6:f8:d7:ac";
      addresses = {lan = 30;};
    };
    "nanokvm-wifi" = {
      # The AIC8800's burned-in MAC; wlan0 lives on the wifi VLAN.
      mac = "38:7a:cc:40:41:e3";
      addresses = {wifi = 17;};
    };
    claw = {
      # PicoClaw's AIC8800. Keep it below the dynamic pool so the diskless
      # NFS client has the same address in the initrd and stage 2.
      mac = "38:7a:cc:9b:48:62";
      addresses = {wifi = 18;};
    };
    "bambu-a1-mini" = {
      # A1 mini, serial 0300DA651900919. Reserving its current pool lease only
      # to give it a stable name: go2rtc dials the chamber camera by FQDN.
      mac = "94:a9:90:df:c5:c4";
      addresses = {wifi = 37;};
    };
    "strix-strip" = {
      # Tuya Local / Home Assistant power strip for the four Strix hosts.
      mac = "d8:c8:0c:c6:c5:2b";
      addresses = {wifi = 124;};
    };
    "poe-switch-10g" = {addresses = {lan = 23;};};
    # Per-host hardware facts for the Strix fleet live in `strix`:
    #  - beegfsDiskSerial: each node's dedicated 4 TB BeeGFS NVMe, by serial
    #    (CX5/SSD PCIe enumeration order differs between the four boxes, so
    #    destructive disko runs must never address by nvme0n1).
    #  - cx5Port: which port of this node's own ConnectX-5 is cabled. Each node
    #    has its own card (verified 2026-07-30, distinct base GUIDs), not a
    #    shared multi-host adapter; see the note in machines/x86/strix-halo.
    #  - ryzenAdj: package power limits (1/2 sustain more than 3/4).
    "strix-1" = {
      # eno1 burned-in MAC (confirmed via ethtool -P); the firmware PXE
      # client identifies with this, so dnsmasq netboot tagging depends
      # on it being the real permanent address.
      mac = "84:47:09:68:82:b1";
      addresses = {
        lan = 136;
        fabric = 101;
      };
      # Diskless: firmware UEFI HTTP -> iPXE -> trex HTTP/NFS.
      netboot = true;
      netbootMac = "84:47:09:68:82:b1";
      # The ConnectX-5 identities are deliberately NOT in extraMacs. Netboot is
      # Realtek-only, and 2026-08-08 produced hard evidence for why -- read this
      # before ever adding them back.
      #
      # THE REWIRE PROBLEM. Cabling the aux card into the second M.2 added a
      # second PCIe endpoint with two more PXE-capable functions, and those
      # entries now sit AHEAD of the Realtek in the firmware boot order. At
      # 20:45-20:50 the router logged 27 PXEClient DISCOVERs from
      # 1c:34:da:61:12:98/:99/:9c/:9d and ZERO from eno1: the host cycles the
      # fabric NICs and never reaches the Realtek.
      #
      # WHY TAGGING THEM DOES NOT FIX IT (tried, 2026-08-08 21:01). With the
      # CX5 MACs tagged, firmware PXE happily DHCPs, resolves to this host's own
      # static lease, and pulls snponly.efi over TFTP -- exactly once, cleanly.
      # And then nothing: the router saw NO conntrack entry and NO established
      # :80 connection from 192.168.23.136/.25/.26, and trex served 862 kB total
      # (one initrd is 68 MB). iPXE's embedded script is `dhcp || exit` followed
      # by three `chain` attempts, so zero TCP SYNs means its OWN dhcp failed
      # and it exited before attempting the chain.
      #
      # The fabric NIC works for the FIRMWARE's PXE stack but not for a driver
      # layered on top of it. The same shape killed a kexec into the netboot
      # kernel on strix-2 the same evening: mlx5_core came up with every module
      # present (verified by nix eval, not guesswork) and never reached DHCP.
      # Note also that iPXE has no usable ConnectX-5 native driver, so the
      # full-ipxe.efi workaround cannot rescue a CX5-only path either.
      #
      # Tagging them is therefore worse than useless: it hands the firmware a
      # boot file it cannot follow, burning the attempt that might otherwise
      # have fallen through to the Realtek.
      strix = {
        beegfsDiskSerial = "A632B32900OTVY";
        beegfsFsUUID = "8c4b594f-72e6-4575-996d-00d2f127c745";
        # Serving is disabled on Strix-1 by operator request; do not start
        # the coordinator or open its inference listener on this host.
        ds4Serve = false;
        cx5Port = 1;
        # 2026-09-16 physical canary audit: only the Ethernet-mode CX5
        # (:b4/:b5, MT27800) enumerates; the previously selected CX7
        # (10:70:fd:91:c5:90, adopted 2026-08-26) is absent from PCI.
        # Restore the earlier f1np1 primary, selected by permanent MAC rather
        # than its changing BDF. This port has 100GbE carrier to CRS812 and
        # its ARP probe reaches trex-rdma at the expected 50:6b:4b:0d:24:86.
        # Matching the absent CX7 left both live CX5 ports unaddressed.
        cx5FabricMac = "1c:34:da:61:12:b5";
        ryzenAdj = {
          # stapm = 75000;
          # fast = 75000;
          # slow = 75000;
          stapm = 132000;
          fast = 176000;
          slow = 154000;
          apuSlow = 154000;
        };
      };
    };
    "strix-2" = {
      # Burned-in eno1 MAC observed from the firmware HTTPClient.
      mac = "84:47:09:68:79:a6";
      # extraMacs REMOVED 2026-08-08. It listed 1c:34:da:61:12:99/:9c/:9d,
      # which `ethtool -P` proved are in *strix-1's* chassis (this host holds
      # :b0/:b1 and :b4/:b5 -- two independent CX5 ASICs, confirmed live
      # 2026-08-08 19:39). Keeping them here had one real, non-theoretical
      # effect: the router emitted
      #   dhcp-host=84:47:09:68:79:a6,1c:34:da:61:12:99,:9c,:9d,192.168.23.192
      # so strix-1's CX5 ports took strix-2's LAN address on any DHCP they did.
      #
      # The prior comment justified leaving them by saying the side effect was
      # that "strix-1's fabric card is netboot-tagged as strix-2". That is not
      # what happens: profiles/router/services.nix builds netbootMacs only over
      # `netbootHosts`, which filters on `netboot`, and this host is
      # `netboot = false` -- so no set:netboot tag was ever emitted for them.
      # The static lease was the whole of it, and it is worth removing.
      addresses = {
        lan = 192;
        fabric = 102;
      };
      # LOCAL DISK, not netboot (corrected 2026-07-30). This host boots from
      # /dev/sda: GPT labels strix-2-ESP (vfat) and strix-2-root (btrfs,
      # subvol=@root), exactly what the !netboot branch of
      # machines/x86/strix-halo/default.nix expects. It has three local
      # generations and mounts no NFS store.
      #
      # It was declared netboot = true, but netboot here could never have
      # worked: the identities below name 1c:34:da:61:12:99/:9c/:9d, which
      # `ethtool -P` proves are in *strix-1's* chassis -- this host holds
      # :b0/:b1. The two nodes' CX5 identities were transposed, so dnsmasq
      # never tagged strix-2, PXE never matched, and the firmware fell through
      # to the local disk. The flag described an intent, not reality.
      #
      # Diskless, like every other strix (2026-08-08). The strix hosts are
      # ALWAYS netbooted; there is no local-disk variant of this machine class.
      #
      # Firmware PXE was recovered in Setup on 2026-08-15: enable the UEFI
      # Network Stack and IPv4 PXE, put Network ahead of USB, and set both
      # ConnectX-5 ports' Legacy Boot Protocol to None so they cannot intercept
      # the attempt. A cold test from eno1 fetched snponly.efi, the per-MAC
      # script, kernel, and complete initrd. The Rock-5B/full-ipxe USB gadget is
      # therefore only a recovery KVM now, not part of this host's boot chain.
      #
      # Previously `netboot = false`, with netbootMac/netbootLinuxMac naming
      # strix-1's :9d/:99 -- a leftover of the 2026-07-30 transposition fix,
      # which corrected cx5FabricMac and netboot but not these.
      netboot = true;
      # THIS chassis's Realtek. strix-2's CX5 identities are :b0/:b1 and
      # :b4/:b5 (two independent ASICs, confirmed live 2026-08-08 19:39) and
      # are deliberately absent, exactly as on strix-1: the firmware must not
      # be able to PXE from a fabric card.
      netbootMac = "84:47:09:68:79:a6";
      # netbootSharesFabric dropped (2026-07-30): it put the fabric address on
      # eno1, and eno1 here is the 2.5G Realtek, so the RoCE address landed on
      # the slow NIC with no verbs device -- NVMe-oF could never bind it. With
      # the flag gone, 10-cx5-fabric renames the CX5 to cx5fabric0 and
      # 15-cx5-fabric gives it the fabric address at MTU 9000. The NFS netboot
      # root is unaffected: it runs over eno1's *LAN* address to 192.168.23.8.
      strix = {
        beegfsDiskSerial = "A632B32900P0HW";
        beegfsFsUUID = "f5284213-637e-4911-bad0-0dbc77fcf9ca";
        # Passive V620 cooling cannot sustain the stock 4 x 250 W load.
        # Start at 180 W per card; validate sustained temperatures after boot.
        v620 = { powerLimitWatts = 180; count = 4; };
        cx5Port = 1;
        # The BlueField-2 that temporarily carried this identity was removed
        # from the PEX88096 on 2026-08-28. Promote the remaining M.2-slot CX5's
        # live, cabled f1np1 port to the primary fabric role: it trains at
        # 100 Gb/s and was verified carrying 192.168.25.102 -> trex's
        # 192.168.25.208 NVMe/RDMA export. Matching its permanent MAC keeps the
        # cx5fabric0 name stable across PCI enumeration and future reboots.
        cx5FabricMac = "1c:34:da:61:12:b1";
        # This netboot root is on eno1, so resetting the independent CX5 before
        # network-online cannot strand NFS. The DAC path needs the explicit
        # 100G force after PCI resets; it previously received that through the
        # secondary-rail unit before this port became the primary.
        forcePrimaryFabricLink = true;
        ryzenAdj = {
          # stapm = 75000;
          # fast = 75000;
          # slow = 75000;
          stapm = 132000;
          fast = 176000;
          slow = 154000;
          apuSlow = 154000;
        };
      };
    };
    "strix-3" = {
      mac = "84:47:09:80:64:50";
      addresses = {
        lan = 25;
        fabric = 103;
      };
      netboot = true;
      netbootMac = "84:47:09:80:64:50";
      # BlueField identities are NOT netboot-tagged. Tagging b8:ce:f6:f8:d7:aa
      # was tried on 2026-08-08 and failed the same way as strix-1's CX5: the
      # DPU PXEs, fetches snponly.efi once, and iPXE then exits without ever
      # opening a TCP connection. See the long note on strix-1.
      #
      # Live host enumeration after the 2026-08-14 PCIe rework supersedes the
      # earlier switch-table inference: :e8/:e9 are local ConnectX-5 ports on
      # strix-3. The BlueField remains present but is not the host data path.
      strix = {
        beegfsDiskSerial = "A632B32900OYLN";
        beegfsFsUUID = "596ed632-efbc-4038-9fca-b5400f41d24d";
        cx5Port = 1;
        # The BlueField remains separately managed, but the host fabric seen
        # after the 2026-08-14 PCIe rework is this dual-port ConnectX-5.
        bluefield = true;
        # Live permanent MACs, carrier, and LLDP verified 2026-08-14. As on
        # the other nodes, f1np1 is the primary rail and f0np0 is rail 2.
        cx5FabricMac = "b8:59:9f:54:db:e9";
        # Strix 3/4 currently clamp package requests to these values.
        ryzenAdj = {
          # stapm = 75000;
          # fast = 75000;
          # slow = 75000;
          stapm = 120000;
          fast = 160000;
          slow = 140000;
          apuSlow = 140000;
        };
      };
    };
    "strix-4" = {
      mac = "84:47:09:81:22:35";
      addresses = {
        lan = 26;
        fabric = 104;
      };
      netboot = true;
      netbootMac = "84:47:09:81:22:35";
      # CX5 identities are NOT netboot-tagged; tagging them was tried on
      # 2026-08-08 and failed identically to strix-1 (iPXE loads, then exits
      # without a single TCP SYN). See the long note on strix-1.
      #
      # Live 2026-08-14 enumeration shows this chassis owns :e4/:e5; the old
      # switch-table inference that also assigned :e8/:e9 here was wrong.
      strix = {
        beegfsDiskSerial = "A632B32900OZJS";
        beegfsFsUUID = "608e561f-e19a-4199-984f-b950fccce3e3";
        cx5Port = 1;
        cx5FabricMac = "b8:59:9f:54:db:e5";
        # Live 2026-08-14: f0np0 is the second port of this chassis's card.
        ryzenAdj = {
          # stapm = 75000;
          # fast = 75000;
          # slow = 75000;
          stapm = 120000;
          fast = 160000;
          slow = 140000;
          apuSlow = 140000;
        };
      };
    };
  };

  # Physical/logical network attachment points that are shared by multiple
  # host profiles or by out-of-band device configuration.
  ports = {
    router = {
      lanBridge = "br0.lan";
      # Four on-board Intel I226-V ports. Match their permanent MACs rather
      # than PCI-derived names: removing the CX4/RTL8127 changed enumeration,
      # and networkd observed a second rename pass during the 2026-08-29 boot.
      onboardLan = [
        { linuxName = "lan0"; mac = "a8:b8:e0:04:19:4d"; }
        { linuxName = "lan1"; mac = "a8:b8:e0:04:19:4e"; }
        { linuxName = "lan2"; mac = "a8:b8:e0:04:19:4f"; }
        { linuxName = "lan3"; mac = "a8:b8:e0:04:19:50"; }
      ];
      wan = {
        linuxName = "enp1s0f0np0";
        mac = "50:6b:4b:03:04:ca";
      };
      lan25g = {
        linuxName = "enp1s0f1np1";
        mac = "50:6b:4b:03:04:cb";
      };
      lan10g = {
        # RTL8127 10G copper. The NIC drops off the PCIe bus on some boots,
        # renumbering the whole bus and flapping its kernel name
        # (enp2s0/enp7s0) — pin by MAC so units can reference it.
        linuxName = "lan10g";
        mac = "88:c9:b3:b6:24:30";
      };
      cx5Peer = {
        # Host-local VF backed by the CX5 SharedIO MPFS. Kept in the inventory
        # for firmware experiments; no address is configured on it.
        linuxName = "enp2s0f0v0";
        mac = "02:00:00:00:00:01";
      };
      bluefieldHostPf = {
        # This is the BlueField host PF exposed by the router's PCIe slot;
        # the address is matched by permanent MAC because switchdev can
        # recreate the netdev name during firmware initialization.
        linuxName = "enp1s0f0np0";
        mac = "b8:ce:f6:f8:d7:aa";
      };
    };
    n100.cx5Peer = {
      linuxName = "enp1s0f0v0";
      mac = "02:00:00:00:00:02";
    };
    bluefield2.vppData = {
      linuxName = "enp3s0np0";
      vppName = "bf0";
      mac = "b8:ce:f6:f8:d7:ac";
      pciAddress = "0000:03:00.0";
      switch = {
        host = "mikrotik-crs812";
        port = "qsfp56-1-1";
      };
      link = {
        # The installed HELLAS 200G-labelled cable actually identifies and
        # trains as 100GBASE-CR4 on both ends.
        speedMbps = 100000;
        lanes = 4;
        fec = "rs";
      };
    };
    bluefield2.hostPf = {
      representorName = "pf0hpf";
      vppName = "host-pf0hpf";
      vppMac = "02:00:00:28:00:02";
      # NVIDIA's mlx5 devargs reserve 65535 for the host-PF representor; [0]
      # is VF0. This is consumed only by the attended host-PF DPDK closure.
      dpdkRepresentor = "[65535]";
    };
  };

  # Host-PF acceleration is an optional routed shortcut. The global inventory
  # mode stays off; machine closures select their endpoint independently.
  routing.hostPf = {
    mode = "off";
    network = "bluefieldHostPf";
    # This table is selected only by traffic explicitly bound to the router's
    # /30 address.  The main table and copper default route remain untouched.
    table = 1028;
    rulePriority = 1028;
    router = ports.router.bluefieldHostPf // { address = 1; };
    dpu = ports.bluefield2.hostPf // { address = 2; };
    routes = {
      routerToDpu = [
        "${vlans.fabric.prefix}.0/${toString vlans.fabric.cidr}"
      ];
      dpuToRouter = [
        "${vlans.bluefieldHostPf.prefix}.0/${toString vlans.bluefieldHostPf.cidr}"
      ];
    };
  };

  # Inactive production data for the BlueField router migration.  Consumers
  # render VPP and RouterOS plans from this value; `enable = false` is the
  # hard cut-over gate, so adding facts here cannot take over the live WAN.
  routing.production = {
    enable = false;

    switch = {
      host = "mikrotik-crs812";
      bridge = "bridge";
      bluefieldTrunk = ports.bluefield2.vppData.switch.port;
      # Proved from the live forwarding databases on both ends: this is the
      # CRS812 <-> CRS804 link. CRS804 continues toward CRS510 on its
      # qsfp56-dd-2-1, which CRS510 sees on qsfp28-1-1.
      lanFabricTrunk = "qsfp56-dd-1-1";
    };

    wans = {
      primary = {
        vlanId = 100;
        mtu = 1500;
        switchAccessPort = "sfp56-8";
        lineRateMbps = 25000;
        # Match the live ISP-facing ConnectX-4 settings. sfp56-8 is the empty,
        # reserved ISP cage; sfp56-7 is Rock-5B's live 25G DAC and must not be
        # repurposed (verified on 2026-08-28).
        ethernet = {
          autoNegotiation = false;
          speed = "25G-baseCR";
          fecMode = "fec91";
        };
        ipv4 = {
          method = "dhcp";
          # Keep the old router MAC as an explicit rollback tool, not a hidden
          # default.  Start with the BlueField MAC; clone only if the provider
          # proves to bind the lease to the old client identity.
          leaseCompatibilityMac = ports.router.wan.mac;
          cloneMacAtCutover = false;
        };
        ipv6 = {
          addressMethod = "dhcp6";
          defaultRouteMethod = "router-advertisement";
          prefixDelegation = true;
          requestedPrefixLength = 56;
          # The live provider returned a /48 despite the /56 hint.  Zone IDs
          # remain below 256 so either a /48 or /56 can supply every /64.
          observedPrefixLength = 48;
          prefixGroup = "isp-primary";
        };
        healthTargets = [
          "1.1.1.1"
          "9.9.9.9"
          "2606:4700:4700::1111"
          "2620:fe::fe"
        ];
        qos = {
          txManager = "nixos-wan";
          # The CRS812 ASIC quantizes this to 24.7 Gbit/s.  A 2026-08-30 sweep
          # found this knee immediately below the provider policer: public
          # iPerf still received 23.17 Gbit/s while concurrent RTT stayed near
          # 1 ms instead of stalling behind the ISP queue.
          egressRateMbps = 24700;
        };
      };
      backup = {
        vlanId = vlans.wanBackup.id;
        mtu = vlans.wanBackup.mtu;
        policy = "control-only";
        installDefaultRoute = false;
        # The live CRS812 FDB resolves both of k3's wired MACs behind sfp56-6;
        # that is the management-switch downlink carrying tagged backup
        # transit alongside untagged LAN.
        switchTransit = {
          enable = true;
          edgePort = "sfp56-6";
        };
      };
    };

    zoneOrder = [
      "lan"
      "iot"
      "fabric"
      "guest"
      "mgmt"
      "wifi"
    ];
    zones = {
      lan = {
        network = "lan";
        vlanId = vlans.lan.targetId;
        ipv6SubnetId = "10";
        security = "trusted";
        qosClass = "bestEffort";
      };
      iot = {
        network = "iot";
        vlanId = vlans.iot.id;
        ipv6SubnetId = "20";
        security = "restricted";
        qosClass = "bulk";
      };
      fabric = {
        network = "fabric";
        vlanId = vlans.fabric.id;
        ipv6SubnetId = "25";
        security = "trusted";
        qosClass = "bestEffort";
      };
      guest = {
        network = "guest";
        vlanId = vlans.guest.id;
        ipv6SubnetId = "30";
        security = "isolated";
        qosClass = "bulk";
      };
      mgmt = {
        network = "mgmt";
        vlanId = vlans.mgmt.id;
        ipv6SubnetId = "40";
        security = "management";
        qosClass = "control";
      };
      wifi = {
        network = "wifi";
        vlanId = vlans.wifi.id;
        ipv6SubnetId = "50";
        security = "trusted";
        qosClass = "bestEffort";
      };
    };

    firewall = {
      defaultInterZone = "deny";
      trustedInitiatorZones = ["lan" "fabric" "mgmt" "wifi"];
      # IPv6 remains default-deny. Only forwards explicitly carrying
      # `publishIpv6 = true` are admitted, and the BlueField derives their
      # exact /128s from the live DHCPv6-PD prefix plus each host's stable MAC.
      publishIpv6Services = true;
      strictSourceValidation = true;
    };

    nat44 = {
      sessions = 131072;
      frameQueueLength = 256;
      insideZones = routing.production.zoneOrder;
      outsideWan = "primary";
      # Preserve declared application publications, but retire direct WAN SSH
      # and Tor exposure on the former router itself.
      publicationGroups = ["arr-servers" "router-control" "trex"];
    };

    qosClasses = {
      bestEffort.dscp = 0;
      bulk.dscp = 8;
      streaming.dscp = 34;
      interactive.dscp = 46;
      control.dscp = 56;
    };

    # First production step: move routing without simultaneously splitting
    # the organically-grown inside L2 domain. The BlueField parent remains
    # the untagged LAN/fabric interface; only WiFi and the WANs are tagged.
    # This is replaced by `zones` after the gateway handoff is accepted.
    transition = {
      enable = false;
      mode = "legacy-flat";
      legacyInside = {
        networks = ["lan" "fabric"];
        mtu = vlans.fabric.mtu;
        ipv6SubnetId = "10";
        # The pre-migration flat LAN already uses subnet zero of the ISP /48.
        # Keep that GUA on the transition parent so existing addresses remain
        # routable; VLAN 10 becomes the LAN GUA only in the final split design.
        delegatedSubnetId = "0";
      };
      taggedZones = ["wifi"];
      deferredFinalZones = ["lan" "iot" "fabric" "guest" "mgmt"];
      switch = {
        legacyPvid = 1;
        bluefieldPortMode = "hybrid";
        legacyUplink = routing.production.switch.lanFabricTrunk;
        preserveLabVlans = true;
      };
      # K3 and its iPhone remain an out-of-band recovery endpoint. VPP never
      # installs a default through k3; the phone is not a production WAN.
      controlPlane = {
        # Keep the old router as an ordinary service host. It first acquires
        # this secondary address while still owning .1; DHCP then advertises
        # .31 for DNS/netboot. Only after leases and static clients migrate
        # does VPP take the .1 gateway addresses.
        host = "router";
        # Direct CRS812 RJ45 attachment after removing the intervening
        # management switch from the service VLAN path (2026-08-29).
        switchPort = "ether2";
        targetHost = 31;
        targetIp = ipOf "lan" routing.production.transition.controlPlane.targetHost;
        targetIpv6 = "fdde:ad:10::31";
        currentGatewayIp = gatewayIp "lan";
        services = ["dns" "dhcp" "tftp" "netboot-http" "wireguard"];
        routedIpv4 = [
          "${vlans.wireguard.prefix}.0/${toString vlans.wireguard.cidr}"
          hydraBuilders.subnet
        ];
        routedIpv6 = ["fdde:ad:24::/64"];
      };
    };
  };

  # Reserved for future iterations. Keep keys present so consumers can import without churn.
  services = {};

  # HTTP port on trex serving iPXE scripts/kernels/initrds for hosts
  # marked `netboot = true` (see profiles/netboot-{server,client}.nix and
  # the TFTP/dhcp-boot wiring in profiles/router/services.nix).
  # Keep firmware HTTP Boot on the conventional port. The Strix UEFI client
  # accepts DHCP but does not attempt TCP when an explicit :8020 is present.
  netbootHttpPort = 80;

  # ---- Helpers (derived views) ----

  # "lan" 7  ->  "192.168.23.7"
  ipOf = vlanName: octet: "${vlans.${vlanName}.prefix}.${toString octet}";

  # Gateway IP of a vlan: gatewayIp "lan"  ->  "192.168.23.1"
  gatewayIp = vlanName: ipOf vlanName vlans.${vlanName}.gatewayHost;

  # Convenient shortcut for the lan gateway (the universal "router").
  routerIp = gatewayIp "lan";
  # Routing and local network services deliberately separate during the VPP
  # handoff. `routerIp` remains the gateway; this address remains on the old
  # router after it becomes an ordinary LAN service host.
  controlPlaneIp = routing.production.transition.controlPlane.targetIp;
  dnsIp = controlPlaneIp;
  netbootIp = controlPlaneIp;

  # "lan" 14  ->  "192.168.23.14/24"
  cidrOf = vlanName: octet: "${ipOf vlanName octet}/${toString vlans.${vlanName}.cidr}";

  # "trex"  ->  "trex.lan.satanic.link"   (internal LAN FQDN)
  fqdn = name: "${name}.${domains.lan}";

  # "trex"  ->  "trex.satanic.link"   (public-facing FQDN)
  publicFqdn = name: "${name}.${domains.public}";

  # The host's "primary" IP, used for DNS aliases. lan if present, else first vlan key.
  primaryIp = h: let
    vlanNames = builtins.attrNames h.addresses;
    pick =
      if builtins.elem "lan" vlanNames
      then "lan"
      else builtins.head vlanNames;
  in
    ipOf pick h.addresses.${pick};

  # NixOS networking.hosts shape: { "192.168.23.1" = [ "router" "frigate" ]; ... }
  # Aggregates all of a host's VLAN IPs and folds extraNames onto the primary.
  toNixosHosts = let
    flat = lib.flatten (lib.mapAttrsToList
      (name: h:
        lib.mapAttrsToList
        (vlanName: octet: {
          ip = ipOf vlanName octet;
          names = [name] ++ lib.optionals (ipOf vlanName octet == primaryIp h) (h.extraNames or []);
        })
        h.addresses)
      hosts);
  in
    lib.foldl'
    (acc: e: acc // {${e.ip} = (acc.${e.ip} or []) ++ e.names;})
    {}
    flat;

  # dnsmasq dhcp-host shape: ["mac[,mac...],ip" ...] for every host that has a
  # MAC. A host may list extraMacs (other NICs on the same box); dnsmasq accepts
  # multiple hardware addresses sharing one reserved IP on a single dhcp-host
  # line, so each NIC resolves to the host's primary IP rather than a pool lease.
  toDnsmasqDhcpHost =
    lib.mapAttrsToList
    (name: h: "${if h ? dhcpClientId then "id:${h.dhcpClientId}" else lib.concatStringsSep "," ([h.mac] ++ (h.extraMacs or []))},${primaryIp h}")
    (lib.filterAttrs (_: h: (h.mac or null) != null) hosts);

  # dnsmasq address shape: ["/fqdn/ip" ...]. Each host (and each of its
  # extraNames) gets bare, lan-FQDN and public-FQDN records, all pointing at
  # the primary IP. Generates a superset of the prior hand-written list.
  toDnsmasqAddress = let
    namesFor = name: h: [name] ++ (h.extraNames or []);
    recordsFor = name: h: let
      ip = primaryIp h;
    in
      lib.flatten (map
        (n: [
          "/${n}/${ip}"
          "/${n}.${domains.lan}/${ip}"
          "/${n}.${domains.public}/${ip}"
        ])
        (namesFor name h));
  in
    lib.flatten (lib.mapAttrsToList recordsFor hosts);
}
