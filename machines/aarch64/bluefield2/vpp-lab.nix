{
  config,
  lib,
  pkgs,
  network,
  ...
}: let
  topology = import ./vpp-lab-topology.nix {
    inherit network;
    driver = config.bluefield2.vpp.dataplaneDriver;
    hostPfMode = config.bluefield2.hostPf.mode;
  };
  inherit (topology) dataInterface dataMac dataName;
  useDpdk = topology.dataplane.driver == "dpdk";
  useRdma = topology.dataplane.driver == "rdma";
  useHostPfRepresentor = config.bluefield2.hostPf.mode == "vpp-representor";
  workerCount = builtins.length topology.dataplane.workerCores;
  workerCoreList = lib.concatMapStringsSep "," toString topology.dataplane.workerCores;

  # The repository overlay repairs nixpkgs' generic AArch64 DPDK cross file.
  # A later, deliberately tiny cross file selects the actual target SoC; Meson
  # merges cross files in order, so this retains the toolchain repair while
  # allowing the topology to choose DPDK's supported BlueField platform.
  dpdkPlatformFile = pkgs.writeText "dpdk-${topology.dataplane.dpdkPlatform}-platform.conf" ''
    [properties]
    platform = '${topology.dataplane.dpdkPlatform}'
  '';
  dataplaneDpdk = pkgs.dpdk.overrideAttrs (oldAttrs:
    lib.optionalAttrs useDpdk {
      mesonFlags =
        map
          (flag:
            if flag == "-Denable_docs=true"
            then "-Denable_docs=false"
            else flag)
          (oldAttrs.mesonFlags or [])
        ++ [
          "--cross-file=${dpdkPlatformFile}"
          "-Denable_drivers=${lib.concatStringsSep "," topology.dataplane.dpdkDrivers}"
        ];
      # nixpkgs declares a separate `doc` output unconditionally.  With the
      # target-emulated Sphinx build disabled, keep that output valid but empty.
      postInstall =
        (oldAttrs.postInstall or "")
        + ''
          mkdir -p "$doc/share/doc/dpdk"
        '';
    });

  zone = name: topology.zones.${name};
  zones = map zone topology.zoneOrder;
  interfaceName = z: "${dataName}.${toString z.subId}";
  ipv4Host = z: host: "${z.ipv4.prefix}.${toString host}";
  ipv4Address = z: host: "${ipv4Host z host}/${toString z.ipv4.cidr}";
  ipv4Network = z: "${z.ipv4.prefix}.0/${toString z.ipv4.cidr}";
  ipv6Host = z: host: "${z.ipv6.prefix}::${toString host}";
  ipv6Address = z: host: "${ipv6Host z host}/${toString z.ipv6.cidr}";
  ipv6Network = z: "${z.ipv6.prefix}::/${toString z.ipv6.cidr}";

  trusted = zone "trusted";
  wan = zone "wan";
  restricted = zone "restricted";
  backupWan = topology.backupWan;
  backupInterfaceName = "${dataName}.${toString backupWan.subId}";
  backupIpv4Host = host: "${backupWan.ipv4.prefix}.${toString host}";
  backupIpv4Address = host: "${backupIpv4Host host}/${toString backupWan.ipv4.cidr}";
  qbittorrent = topology.services.qbittorrent;
  qbittorrentTarget = zone qbittorrent.targetZone;
  restrictedTest = topology.services.restrictedTest;
  restrictedTestSource = zone restrictedTest.sourceZone;
  restrictedTestTarget = zone restrictedTest.targetZone;
  natOutside = zone topology.nat44.outsideZone;
  qosTos = className: topology.qosClasses.${className}.dscp * 4;
  # IPv4 and TCP have 20-byte base headers.  Derive the advertised MSS from
  # the modeled WAN MTU so the LAN's jumbo MTU cannot leak into Internet SYNs.
  natMss = wan.mtu - 20 - 20;

  backupInterfaceCommands = lib.concatStringsSep "\n" [
    "create sub-interfaces ${dataName} ${toString backupWan.subId}"
    "set interface mtu packet ${toString backupWan.mtu} ${backupInterfaceName}"
    "set interface state ${backupInterfaceName} up"
    "set interface ip address ${backupInterfaceName} ${backupIpv4Address backupWan.ipv4.localHost}"
  ];
  backupBootstrapCommands = lib.optionalString backupWan.bootstrap.enable (
    "set interface ip address ${backupWan.bootstrap.interface} ${backupWan.bootstrap.localAddress}"
  );
  backupRouteInterface =
    if backupWan.bootstrap.enable
    then backupWan.bootstrap.interface
    else backupInterfaceName;
  backupRoutePeer =
    if backupWan.bootstrap.enable
    then backupWan.bootstrap.peerAddress
    else backupIpv4Host backupWan.ipv4.peerHost;
  backupRouteCommands = lib.optionalString backupWan.installTestRoutes (
    lib.concatMapStringsSep "\n"
      (destination: "ip route add ${destination} via ${backupRoutePeer} ${backupRouteInterface}")
      backupWan.testRoutes
  );

  interfaceCommands = lib.concatStringsSep "\n" (
    map (z: "create sub-interfaces ${dataName} ${toString z.subId}") zones
    ++ map (z: "set interface mtu packet ${toString z.mtu} ${interfaceName z}") zones
    ++ map (z: "set interface state ${interfaceName z} up") zones
    ++ map (z: "set interface ip address ${interfaceName z} ${ipv4Address z z.ipv4.localHost}") zones
    ++ map (z: "set interface ip address ${interfaceName z} ${ipv6Address z z.ipv6.localHost}") zones
  );

  qosValues = lib.unique (map (z: qosTos z.qosClass) zones);
  qosMapEntries = lib.concatStringsSep " " (map (value: "[ip][${toString value}]=${toString value}") qosValues);
  qosCommands = lib.concatStringsSep "\n" (
    ["qos egress map id 0 ${qosMapEntries}"]
    ++ map (z: "qos store ip ${interfaceName z} value ${toString (qosTos z.qosClass)}") zones
    ++ map (z: "qos mark ip ${interfaceName z} id 0") zones
  );

  natCommands = lib.concatStringsSep "\n" (
    [
      "set nat frame-queue-nelts ${toString topology.nat44.frameQueueLength}"
      "nat44 plugin enable sessions ${toString topology.nat44.sessions}"
      "nat mss-clamping ${toString natMss}"
      "nat44 add address ${ipv4Host natOutside natOutside.ipv4.localHost}"
    ]
    ++ map (name: "set interface nat44 in ${interfaceName (zone name)}") topology.nat44.insideZones
    ++ ["set interface nat44 out ${interfaceName (zone topology.nat44.outsideZone)}"]
    ++ map (protocol: "nat44 add static mapping ${protocol} local ${ipv4Host qbittorrentTarget qbittorrentTarget.ipv4.peerHost} ${toString qbittorrent.port} external ${ipv4Host natOutside natOutside.ipv4.localHost} ${toString qbittorrent.port}")
    qbittorrent.protocols
  );

  renderAclRule = rule:
    "${rule.action} src ${rule.src} dst ${rule.dst}"
    + lib.optionalString (rule ? proto) " proto ${toString rule.proto}"
    + lib.optionalString (rule ? dport) " dport ${toString rule.dport}";
  aclDefinitions = {
    restricted = {
      tag = "vpp-lab-restricted";
      rules = [
        {
          action = "permit";
          src = ipv4Network restrictedTestSource;
          dst = "${ipv4Host restrictedTestTarget restrictedTestTarget.ipv4.peerHost}/32";
          proto = restrictedTest.protocol;
          dport = restrictedTest.port;
        }
        {
          action = "deny";
          src = "0.0.0.0/0";
          dst = "0.0.0.0/0";
        }
        {
          action = "permit";
          src = ipv6Network restrictedTestSource;
          dst = "ff02::/16";
          proto = 58;
        }
        {
          action = "permit";
          src = ipv6Network restrictedTestSource;
          dst = "${ipv6Host restrictedTestSource restrictedTestSource.ipv6.localHost}/128";
          proto = 58;
        }
        {
          action = "permit";
          src = ipv6Network restrictedTestSource;
          dst = "${ipv6Host restrictedTestTarget restrictedTestTarget.ipv6.peerHost}/128";
          proto = restrictedTest.protocol;
          dport = restrictedTest.port;
        }
        {
          action = "deny";
          src = "::/0";
          dst = "::/0";
        }
      ];
    };
    trusted = {
      tag = "vpp-lab-trusted";
      rules = [
        {
          action = "permit";
          src = "0.0.0.0/0";
          dst = "0.0.0.0/0";
        }
        {
          action = "permit";
          src = ipv6Network trusted;
          dst = "ff02::/16";
          proto = 58;
        }
        {
          action = "permit";
          src = ipv6Network trusted;
          dst = "::/0";
        }
        {
          action = "deny";
          src = "::/0";
          dst = "::/0";
        }
      ];
    };
    wan = {
      tag = "vpp-lab-wan";
      rules = [
        {
          action = "permit";
          src = "0.0.0.0/0";
          dst = "0.0.0.0/0";
        }
        {
          action = "permit";
          src = "::/0";
          dst = "::/0";
          proto = 58;
        }
        {
          action = "permit";
          src = "::/0";
          dst = "${ipv6Host qbittorrentTarget qbittorrentTarget.ipv6.peerHost}/128";
          proto = 6;
          dport = qbittorrent.port;
        }
        {
          action = "permit";
          src = "::/0";
          dst = "${ipv6Host qbittorrentTarget qbittorrentTarget.ipv6.peerHost}/128";
          proto = 17;
          dport = qbittorrent.port;
        }
        {
          action = "deny";
          src = "::/0";
          dst = "::/0";
        }
      ];
    };
    wanEgressState = {
      tag = "vpp-lab-wan-egress-state";
      rules = [
        {
          action = "permit";
          src = "0.0.0.0/0";
          dst = "0.0.0.0/0";
        }
        {
          action = "permit";
          src = "::/0";
          dst = "::/0";
          proto = 58;
        }
        {
          action = "permit+reflect";
          src = ipv6Network trusted;
          dst = "::/0";
        }
        {
          action = "permit+reflect";
          src = ipv6Network restricted;
          dst = "::/0";
        }
        {
          action = "deny";
          src = "::/0";
          dst = "::/0";
        }
      ];
    };
  };
  aclIndices = lib.listToAttrs (lib.imap0 (index: name: {
      inherit name;
      value = index;
    })
    topology.aclOrder);
  aclCommands = lib.concatStringsSep "\n" (map (name: let
    definition = aclDefinitions.${name};
  in "set acl-plugin acl ${lib.concatStringsSep ", " (map renderAclRule definition.rules)} tag ${definition.tag}")
  topology.aclOrder);
  aclAttachmentCommands = lib.concatStringsSep "\n" [
    "set acl-plugin interface ${interfaceName trusted} input acl ${toString aclIndices.trusted}"
    "set acl-plugin interface ${interfaceName wan} input acl ${toString aclIndices.wan}"
    "set acl-plugin interface ${interfaceName wan} output acl ${toString aclIndices.wanEgressState}"
    "set acl-plugin interface ${interfaceName restricted} input acl ${toString aclIndices.restricted}"
  ];
in {
  # Isolated VPP proving ground.  The DPU keeps its OOB LAN address and RShim
  # recovery link in Linux; VPP owns only the external ConnectX-6 Dx port.
  # Remove this import from default.nix to return the data port to networkd.

  # The installed HELLAS cable (serial 2606180004) identifies as QSFP28
  # 100GBASE-CR4 even though its vendor part number says 200G.  Speed alone is
  # ambiguous on ConnectX-6 Dx (100G CR2 and CR4 are both supported), so prefer
  # the explicit four-lane request.  Linux 6.12 rejects the lanes netlink
  # attribute after this BlueField enters switchdev, however, while retaining
  # networkd's already-applied 100G mode.  Fall back to the speed-only request
  # and always restore IFF_UP; VPP plus the attended boot guard verify actual
  # carrier and WAN DHCP rather than making an optional ethtool knob fatal.
  systemd.services.bluefield-vpp-lab-link = {
    description = "Force the BlueField VPP lab link to 100GBASE-CR4/RS-FEC";
    after = [
      "systemd-networkd.service"
      "sys-subsystem-net-devices-${dataInterface}.device"
    ];
    wants = ["sys-subsystem-net-devices-${dataInterface}.device"];
    before = ["vpp.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -u
      ${pkgs.iproute2}/bin/ip link set '${dataInterface}' down
      trap '${pkgs.iproute2}/bin/ip link set "${dataInterface}" up || true' EXIT

      if ! ${pkgs.ethtool}/bin/ethtool -s '${dataInterface}' \
           autoneg off speed '${toString topology.link.speedMbps}' \
           lanes '${toString topology.link.lanes}' duplex full; then
        echo "lane selection unsupported; retaining the 100G speed without an explicit lane count" >&2
        ${pkgs.ethtool}/bin/ethtool -s '${dataInterface}' \
          autoneg off speed '${toString topology.link.speedMbps}' duplex full \
          || echo "speed selection unsupported; retaining the mode already applied by networkd" >&2
      fi

      ${pkgs.ethtool}/bin/ethtool --set-fec '${dataInterface}' \
        encoding '${topology.link.fec}' \
        || echo "FEC selection unsupported; retaining the current FEC mode" >&2
      ${pkgs.iproute2}/bin/ip link set '${dataInterface}' up
      trap - EXIT
      ${pkgs.ethtool}/bin/ethtool '${dataInterface}' \
        | ${pkgs.gnugrep}/bin/grep -E 'Speed:|Lanes:|Link detected:|FEC' \
        || true
    '';
  };

  # The mlx5 PMD is bifurcated: mlx5_core owns the PCI function and mlx5_ib
  # supplies the userspace Verbs control endpoint used by DPDK.  The latter
  # was not auto-loaded by udev on the firmware-matched 6.12 kernel, so DPDK saw the PCI
  # allowlist entry but rejected it with "Verbs device not found".  Verify the
  # endpoint after switchdev has settled, and log the eswitch's netdev/port
  # inventory so a missing host representor is diagnosable from the persistent
  # journal after the attended boot guard rolls back.
  systemd.services.bluefield-dpdk-prerequisites = lib.mkIf useDpdk {
    description = "Prepare and verify the BlueField mlx5 DPDK control path";
    after = [
      "systemd-modules-load.service"
      "bluefield-switchdev.service"
    ];
    before = [
      "bluefield-vpp-lab-link.service"
      "vpp.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "25s";
    };
    script = ''
      set -u
      bdf='${topology.dataplane.pciAddress}'
      ${pkgs.kmod}/bin/modprobe mlx5_ib
      ${pkgs.systemd}/bin/udevadm settle --timeout=5 || true

      eswitch="$(${pkgs.coreutils}/bin/timeout 2 \
        ${pkgs.iproute2}/bin/devlink dev eswitch show "pci/$bdf" 2>/dev/null || true)"
      echo "BlueField eswitch state: ''${eswitch:-unavailable}"
      case "$eswitch" in
        *"mode switchdev"*) ;;
        *)
          echo "BlueField eswitch did not enter switchdev; refusing to start VPP DPDK" >&2
          exit 75
          ;;
      esac

      found=0
      for second in $(${pkgs.coreutils}/bin/seq 1 10); do
        for ibdev in /sys/class/infiniband/*; do
          [ -e "$ibdev/device" ] || continue
          if [ "$(${pkgs.coreutils}/bin/basename \
                "$(${pkgs.coreutils}/bin/readlink -f "$ibdev/device")")" = "$bdf" ]; then
            echo "DPDK Verbs device $(${pkgs.coreutils}/bin/basename "$ibdev") owns $bdf"
            found=1
            break 2
          fi
        done
        ${pkgs.coreutils}/bin/sleep 1
      done

      echo "BlueField switchdev port inventory:"
      ${pkgs.iproute2}/bin/devlink port show "pci/$bdf" || true
      echo "BlueField netdev inventory:"
      for netdev in /sys/class/net/*; do
        [ -e "$netdev/phys_switch_id" ] || continue
        switch_id="$(${pkgs.coreutils}/bin/cat "$netdev/phys_switch_id" 2>/dev/null || true)"
        [ -n "$switch_id" ] || continue
        port_name="$(${pkgs.coreutils}/bin/cat "$netdev/phys_port_name" 2>/dev/null || true)"
        echo "$(${pkgs.coreutils}/bin/basename "$netdev") phys_port_name=$port_name phys_switch_id=$switch_id"
      done

      if [ "$found" -ne 1 ]; then
        echo "no mlx5 Verbs device appeared for $bdf; refusing to start VPP DPDK" >&2
        exit 75
      fi
    '';
  };

  # VPP, not Linux, owns the fabric address while the lab is enabled.  Both the
  # RDMA plugin and DPDK's mlx5 PMD are bifurcated drivers: mlx5_core remains
  # bound and provides the control path while VPP owns packet processing.
  systemd.network.networks."90-bluefield-data-ports" = {
    address = lib.mkForce [];
    neighbors = lib.mkForce [];
    networkConfig = {
      DHCP = lib.mkForce "no";
      IPv6AcceptRA = lib.mkForce false;
      LinkLocalAddressing = lib.mkForce "no";
    };
    linkConfig.RequiredForOnline = lib.mkForce "no";
  };

  # Two GiB of 2 MiB hugepages leaves ample RAM for Linux while allowing large
  # VPP buffer pools and later NAT/session tests.
  boot.kernel.sysctl."vm.nr_hugepages" = topology.dataplane.hugepages2MiB;

  services.vpp = {
    enable = true;
    # nixpkgs defaults to VPP's generic AArch64 build, which compiles runtime
    # variants for several unrelated server CPUs.  BlueField 2 uses Cortex-A72
    # cores with 64-byte cache lines; VPP's cn913x platform describes exactly
    # that CPU geometry and produces a single, correctly tuned datapath.
    package =
      (pkgs.vpp.override {
        dpdk = dataplaneDpdk;
        withDpdk = useDpdk;
        withAfXdp = false;
        # python3.withPackages loses Nixpkgs' automatic dependency splicing in
        # this package.  It is a build-time API generator, so use native Python
        # rather than running the target AArch64 interpreter through QEMU.
        python3 = pkgs.buildPackages.python3;
      }).overrideAttrs (oldAttrs: {
        patches =
          (oldAttrs.patches or [])
          ++ [
            ./patches/vpp-dhcpv6-pd-child-ra-lifetime.patch
            ./patches/vpp-dpdk-shared-pci-explicit-name.patch
          ];
        cmakeFlags =
          map (
            flag:
              if flag == "-DVPP_PLATFORM=default"
              then "-DVPP_PLATFORM=cn913x"
              else flag
          )
          oldAttrs.cmakeFlags
          ++ ["-DCMAKE_C_FLAGS=-mtune=cortex-a72"];
        # Nix's AArch64 compiler wrapper injects `-march=armv8-a`; when an
        # explicit -march is present GCC uses -mcpu only for tuning, so VPP's
        # cn913x flag cannot enable AES/PMULL/CRC.  Override the ISA explicitly
        # and keep Cortex-A72 scheduling in CMAKE_C_FLAGS.
        postPatch =
          (oldAttrs.postPatch or "")
          + ''
            substituteInPlace cmake/platform/cn913x.cmake \
              --replace-fail \
                '-mcpu=cortex-a72+crypto' \
                '-march=armv8-a+crc+crypto'
            # VPP 26.06's SNAP input path still queries an empty mhash when no SNAP
            # protocol (for example CDP) has been enabled.  Ordinary background
            # LLC/SNAP frames then crash a worker in mhash_key_sum_8.  An empty
            # protocol vector cannot match, so return before consulting the hash.
            substituteInPlace vnet/snap/snap.h \
              --replace-fail \
                '  p = mhash_get (&sm->protocol_hash, &key);' \
                $'  if (PREDICT_FALSE (vec_len (sm->protocols) == 0))\n    return 0;\n\n  p = mhash_get (&sm->protocol_hash, &key);'
          '';
      });
    settings = {
      cpu = {
        main-core = topology.dataplane.mainCore;
        corelist-workers = workerCoreList;
      };
      buffers = {
        # RDMA needs one 10 KiB SGE for jumbo frames.  DPDK also retains that
        # size because the 2 KiB/scatter trial selected scalar mlx5 RX and
        # exhausted receive WQEs under balanced load.
        buffers-per-numa = topology.dataplane.buffers.perNuma;
        "default data-size" = topology.dataplane.buffers.dataSize.${topology.dataplane.driver};
      };
      memory.main-heap-size = topology.dataplane.mainHeapSize;
      plugins.plugin =
        {
          # Keep the lab deterministic and avoid loading the large set of
          # unrelated plugins (one of which, ioam, is broken in this release).
          default.disable = true;
          "acl_plugin.so".enable = true;
          "nat_plugin.so".enable = true;
          "ping_plugin.so".enable = true;
        }
        // lib.optionalAttrs useHostPfRepresentor {"af_packet_plugin.so".enable = true;}
        // lib.optionalAttrs useDpdk {"dpdk_plugin.so".enable = true;}
        // lib.optionalAttrs useRdma {"rdma_plugin.so".enable = true;};
    }
    // lib.optionalAttrs useDpdk {
      dpdk.iova-mode = topology.dataplane.dpdkIovaMode;
      dpdk.dev.${topology.dataplane.pciAddress} = {
        name = dataName;
        num-rx-queues = workerCount;
        num-tx-queues = workerCount;
        num-rx-desc = topology.dataplane.dpdkRxDescriptors;
        devargs = topology.dataplane.dpdkDevargs;
      };
    };
    startupConfig = ''
      ${lib.optionalString useRdma ''
        # Direct Verbs RX works on this BlueField/firmware combination, but DV
        # TX completes every frame with an error.  Standard ibverbs is the
        # reliable RDMA baseline for this lab.
        create interface rdma host-if ${dataInterface} name ${dataName} num-rx-queues ${toString workerCount} mode ibv
      ''}
      # Preserve the physical address used by the fabric's static neighbours
      # and peers.  DPDK inherits it; only RDMA generates a random address.
      ${lib.optionalString useRdma "set interface mac address ${dataName} ${dataMac}"}
      set interface mtu packet 9000 ${dataName}
      set interface state ${dataName} up

      ${lib.concatStringsSep "\n" (map (address: "set interface ip address ${dataName} ${address}") topology.baseAddresses)}

      # Router-on-a-stick proving ground.  These are ordinary tagged Ethernet
      # subinterfaces carried only on the Trex -> CRS804 -> CRS812 -> BlueField
      # lab trunk.  They exercise the production datapath and avoid VPP's
      # p2p-ethernet shim, which is not stable under parallel load.
      #   trusted LAN       ${ipv4Network trusted}
      #   simulated WAN     ${ipv4Network wan} (TEST-NET-3)
      #   restricted guest ${ipv4Network restricted}
      # LAN can remain jumbo, but the simulated WAN deliberately models the
      # Internet's 1500-byte path MTU.  VPP then generates IPv6 Packet Too Big
      # correctly instead of hiding a production PMTUD failure in the lab.
      ${interfaceCommands}

      # Control-only iPhone failover transit to the selected edge host.
      # Bringing the tagged link up is harmless; test route injection remains
      # behind topology.backupWan.installTestRoutes until it has a phone lease.
      ${backupInterfaceCommands}
      ${backupBootstrapCommands}
      ${backupRouteCommands}

      # Demonstrate the production QoS trust boundary.  Do not trust endpoint
      # DSCP: assign a class from the ingress zone, then mark the packet on
      # every routed egress.  Value ${toString (qosTos "bulk")} is the complete
      # IPv4 ToS / IPv6 traffic class byte for CS1 (DSCP
      # ${toString topology.qosClasses.bulk.dscp}).  In production the restricted interface is
      # the dedicated bulk/qBittorrent VLAN; interactive and streaming VLANs
      # receive their own policy classes.  VPP classifies and marks here, while
      # the CRS812 performs actual ETS scheduling and WAN-rate shaping.
      ${qosCommands}

      # Endpoint-dependent NAT supplies stateful IPv4 WAN traversal.  This
      # shared-interface lab pins the simulated public address explicitly;
      # production can track the address of its dedicated WAN subinterface.
      # The generated static mappings exercise qBittorrent's TCP+UDP port
      # ${toString qbittorrent.port}, defined once in vpp-lab-topology.nix.
      # NAT44-ED defaults to just 64 inter-worker frames, which drops ordinary
      # TCP microbursts well below the 100G link rate.  This must be set before
      # the plugin is enabled; ${toString topology.nat44.frameQueueLength} frames still bounds the queue while giving
      # the six Cortex-A72 workers enough room to absorb a 25G WAN burst.
      ${natCommands}

      # ACL indices are deterministic because these are created in order in a
      # fresh VPP process.  NAT44-ED owns IPv4 connection state.  IPv6 is not
      # translated: LAN zones have stateless ingress policy, while permitted
      # Internet-bound flows acquire state on WAN egress.  Reflection belongs
      # there because ACL sessions are interface/direction scoped; reflecting
      # on LAN input cannot authorize the returning packet on WAN input.
      #
      # WAN permits ICMPv6 control traffic for ND and PMTUD plus qBittorrent's
      # published TCP/UDP port.  The documentation prefixes keep this lab
      # isolated; production will substitute the ISP-delegated /48 via the
      # Linux control plane rather than introduce NAT66.
      # VPP 26.06 accepts exactly one ACL index per interface/direction CLI
      # command.  Keep each zone's IPv4 and IPv6 rules in one mixed-family ACL
      # rather than relying on the multi-index syntax accepted by 26.02.
      ${aclCommands}
      ${aclAttachmentCommands}
    '';
  };

  systemd.services.vpp = {
    after = ["bluefield-vpp-lab-link.service"]
      ++ lib.optional useDpdk "bluefield-dpdk-prerequisites.service";
    requires = ["bluefield-vpp-lab-link.service"]
      ++ lib.optional useDpdk "bluefield-dpdk-prerequisites.service";
  };

  environment.systemPackages = [
    pkgs.iperf3
    pkgs.tcpdump
  ];
}
