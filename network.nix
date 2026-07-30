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
    # High-speed MLX5/BlueField fabric. Hosts use the CRS804 SVI as their
    # gateway; traffic within the subnet stays in the Marvell switch ASIC.
    fabric = {
      id = 25;
      prefix = "192.168.25";
      cidr = 24;
      mtu = 9000;
      gatewayHost = 1;
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
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILK1X7cjrqtB/Yvlkq0kvNix/9t6TNxV9BhzyabPXpWt";
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
      ipv4 = "192.168.23.247";
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
      };
      extraNames = ["frigate"];
    };
    "mikrotik-10g" = {
      mac = "e4:8d:8c:a8:de:40";
      addresses = {lan = 2;};
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
      addresses = {lan = 6;};
    };
    fuckup = {
      mac = "b8:6f:35:ab:31:89";
      addresses = {lan = 7;};
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
      };
      extraNames = ["jellyfin" "grafana" "home" "radarr" "sonarr" "autobrr" "open-webui" "cache" "kimi"];
    };
    # Trex's RoCE endpoint: a ConnectX-4 SR-IOV VF in the host namespace
    # (mlxlan0v1 / mlx5_1). The OVS internal port ovs-host cannot serve RDMA
    # because it is a software port with no verbs device, so RDMA consumers
    # (SPDK NVMe-oF target, NFS/BeeGFS over RDMA) bind this address instead.
    # Traffic leaves via the VF's switchdev representor into the ovs-mlx bridge.
    # MAC last octet 0xd0 == 208 to mirror the host octet.
    "trex-rdma" = {
      mac = "52:6b:4b:0d:24:d0";
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
    "mikrotik-100g" = {
      mac = "48:a9:8a:93:42:4c";
      addresses = {lan = 9;};
    };
    "mikrotik-400g" = {
      mac = "d0:ea:11:d1:9d:a5";
      addresses = {
        lan = 27;
        fabric = 1;
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
    "rock-5b" = {
      mac = "00:e0:4c:68:02:e7";
      addresses = {lan = 18;};
    };
    k3 = {
      mac = "50:0a:52:0b:e5:6f";
      extraMacs = [
        "50:0a:52:0b:81:20"
      ];
      addresses = {lan = 19;};
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
      };
    };
    "nanokvm-wifi" = {
      # The AIC8800's burned-in MAC; wlan0 lives on the wifi VLAN.
      mac = "38:7a:cc:40:41:e3";
      addresses = {wifi = 17;};
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
    #  - cx5Port: which port of the shared multi-host ConnectX-5 this node
    #    owns (pairs 1+2 and 3+4 share a NIC; ports checked out per host).
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
      # Netboot is via the onboard 2.5G Realtek ONLY (proven working
      # 2026-07-29). The ConnectX-5 identities are deliberately absent from
      # extraMacs so the firmware cannot PXE from the fabric card; the CX5 is
      # the RoCE fabric port and nothing else.
      #
      # 2026-07-30: this comment previously described the CX5 as "PXE
      # 1c:34:da:61:12:b4, permanent :b1, aux :b5". That is strix-2's card.
      # `ethtool -P` on the running host reports this chassis holds
      # 1c:34:da:61:12:98 (f0np0) and :99 (f1np1); the :b0/:b1 pair is in
      # strix-2. The strix-1 and strix-2 CX5 identities were transposed.
      netbootMac = "84:47:09:68:82:b1";
      strix = {
        beegfsDiskSerial = "A632B32900OTVY";
        beegfsFsUUID = "8c4b594f-72e6-4575-996d-00d2f127c745";
        cx5Port = 1;
        # Port f1np1 of this chassis's card, matching cx5Port = 1. Verified by
        # ethtool -P on strix-1 (2026-07-30). Was :b1, which is in strix-2.
        cx5FabricMac = "1c:34:da:61:12:99";
        ryzenAdj = {
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
      extraMacs = [
        "1c:34:da:61:12:99"
        "1c:34:da:61:12:9c"
        "1c:34:da:61:12:9d"
      ];
      addresses = {
        lan = 192;
        fabric = 102;
      };
      netboot = true;
      # WARNING (2026-07-30): these three netboot identities and the extraMacs
      # list above all name 1c:34:da:61:12:99/:9c/:9d, which `ethtool -P`
      # proves are in *strix-1's* chassis -- this host holds :b0/:b1. The two
      # nodes' CX5 identities were transposed. They are left untouched because
      # netboot currently works and retagging a diskless host's PXE identity
      # risks stranding it; note the consequence that strix-1's fabric card is
      # netboot-tagged as strix-2, contradicting strix-1's own comment that it
      # deliberately cannot PXE from the CX5.
      netbootMac = "1c:34:da:61:12:9d";
      netbootLinuxMac = "1c:34:da:61:12:99";
      # netbootSharesFabric dropped (2026-07-30): it put the fabric address on
      # eno1, and eno1 here is the 2.5G Realtek, so the RoCE address landed on
      # the slow NIC with no verbs device -- NVMe-oF could never bind it. With
      # the flag gone, 10-cx5-fabric renames the CX5 to cx5fabric0 and
      # 15-cx5-fabric gives it the fabric address at MTU 9000. The NFS netboot
      # root is unaffected: it runs over eno1's *LAN* address to 192.168.23.8.
      strix = {
        beegfsDiskSerial = "A632B32900P0HW";
        beegfsFsUUID = "f5284213-637e-4911-bad0-0dbc77fcf9ca";
        cx5Port = 1;
        # Port f1np1 of this chassis's card, matching cx5Port = 1. Verified by
        # ethtool -P on strix-2 (2026-07-30). Was :99, which is in strix-1.
        cx5FabricMac = "1c:34:da:61:12:b1";
        ryzenAdj = {
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
      # Realtek-only netboot (proven working 2026-07-29). Neither the
      # multi-host CX5 functions (b8:59:9f:54:db:e8/:e9) nor the DPU PXE
      # identity (b8:ce:f6:f8:d7:aa) are netboot-tagged; the DPU's ARM
      # fetches its own leases instead of the host booting through it.
      netbootMac = "84:47:09:80:64:50";
      strix = {
        beegfsDiskSerial = "A632B32900OYLN";
        beegfsFsUUID = "596ed632-efbc-4038-9fca-b5400f41d24d";
        cx5Port = 0;
        # strix-3 hosts the BlueField-2 DPU on its PEX880xx switch: its
        # ConnectX-6 is the fabric NIC. The host PF only inits once the
        # DPU ARM boots, so this host needs the bluefield-host profile
        # (rshim + retrying nic-bind).
        bluefield = true;
        # The DPU's ConnectX-6, which is what this host actually sees: the only
        # mlx5 netdev present is b8:ce:f6:f8:d7:aa (ethtool -P, 2026-07-30).
        # Was b8:59:9f:54:db:e9 -- a function of the multi-host CX5 shared with
        # strix-4, which this host cannot enumerate, so the rename never
        # matched and the fabric address was never assigned at all. Note this
        # MAC is the same identity the comment above calls the "DPU PXE
        # identity"; it is deliberately not netboot-tagged, and using it here
        # only drives the cx5fabric0 rename and the fabric address.
        cx5FabricMac = "b8:ce:f6:f8:d7:aa";
        # Strix 3/4 currently clamp package requests to these values.
        ryzenAdj = {
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
      # Realtek-only netboot (proven working 2026-07-29); the CX5
      # multi-host functions (b8:59:9f:54:db:e4/:e5) stay off the PXE list.
      netbootMac = "84:47:09:81:22:35";
      strix = {
        beegfsDiskSerial = "A632B32900OZJS";
        beegfsFsUUID = "608e561f-e19a-4199-984f-b950fccce3e3";
        cx5Port = 1;
        cx5FabricMac = "b8:59:9f:54:db:e5";
        ryzenAdj = {
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
    };
    n100.cx5Peer = {
      linuxName = "enp1s0f0v0";
      mac = "02:00:00:00:00:02";
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
    (name: h: "${lib.concatStringsSep "," ([h.mac] ++ (h.extraMacs or []))},${primaryIp h}")
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
