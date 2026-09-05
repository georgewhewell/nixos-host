{
  config,
  pkgs,
  lib,
  inputs,
  network,
  ...
}: let
  self = network.hosts.bluefield2;
  trexIp = network.primaryIp network.hosts.trex;
  vppPrometheusExporter = pkgs.callPackage ../../../packages/vpp-prometheus-exporter {};
  oobMac = lib.toLower self.mac;
  oobRenegotiate = pkgs.writeShellScript "bluefield-oob-renegotiate" ''
    for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
      for iface in /sys/class/net/*; do
        [ -e "$iface/address" ] || continue
        if [ "$(${pkgs.coreutils}/bin/cat "$iface/address")" = "${oobMac}" ]; then
          ${pkgs.ethtool}/bin/ethtool -r "$(${pkgs.coreutils}/bin/basename "$iface")" || true
          exit 0
        fi
      done
      ${pkgs.coreutils}/bin/sleep 1
    done
  '';
  bluefieldKernelConfig = with lib.kernel; {
    MELLANOX_PLATFORM = yes;
    MLXBF_BOOTCTL = module;
    MLXBF_PMC = module;
    MLXBF_TMFIFO = module;
  } // lib.optionalAttrs hostPf {
    # mlx5 is a bifurcated DPDK driver: mlx5_core retains the PCI function,
    # while the PMD discovers it through the userspace Verbs endpoint.  Keep
    # these explicit in the firmware-matched 6.12 kernel instead of relying on
    # whichever RDMA defaults that kernel revision happens to select.
    INFINIBAND = module;
    INFINIBAND_USER_ACCESS = module;
    MLX5_INFINIBAND = module;

    # The upstream mlx5 switchdev/representor dataplane is incomplete without
    # MLX5_CLS_ACT.  Its otherwise-easy-to-miss NET_TC_SKB_EXT dependency is
    # disabled in the generic NixOS kernel, so request the complete dependency
    # chain explicitly for host-PF test closures.
    NET_SCHED = yes;
    NET_CLS_ACT = yes;
    NET_TC_SKB_EXT = yes;
    MLX5_CLS_ACT = yes;
  } // lib.optionalAttrs config.services.bluefield2-ipsec-ikev2.kernelOffload.enable {
    # Linux crypto (inline/IPsec-aware) offload only. This deliberately does
    # not enable NVIDIA's packet/full-offload path, which is vendor-patched
    # and documented for Canonical 5.4/5.15 rather than this mainline kernel.
    XFRM_OFFLOAD = yes;
    INET_ESP_OFFLOAD = module;
    INET6_ESP_OFFLOAD = module;
    MLX5_EN_IPSEC = yes;
  };
  hostPfMode = config.bluefield2.hostPf.mode;
  # `linux-bridge` retains the old experiment; `vpp-representor` enables
  # switchdev and exposes the host representor to VPP through native mlx5
  # DPDK, with AF_PACKET retained only as a compatibility fallback.
  hostPf = hostPfMode != "off";
  # With hostPf the kernel must stay era-matched to the NIC firmware
  # (24.40.1000, Apr 2024): on 7.x kernels the external host PF probes but
  # its eswitch datapath silently drops all traffic in both directions
  # (and the original 24.31.x FW couldn't enter switchdev at all). 6.12 LTS
  # (Nov 2024) pairs correctly. Standalone never touches the host vport,
  # so linux_latest is fine there.
  bluefieldKernel =
    if hostPf
    then pkgs.linux_6_12
    else pkgs.linux_latest;
  bluefieldKernelPackages = pkgs.linuxPackagesFor (bluefieldKernel.override {
    structuredExtraConfig = bluefieldKernelConfig;
  });
  imagePkgs = import inputs.nixpkgs {
    system = pkgs.stdenv.buildPlatform.system;
    config = {
      allowUnfree = true;
      allowBroken = true;
    };
    overlays = [
      (final: prev: {
        # disko passes an aggregateModules output as vmTools' kernel. That output
        # includes the kernel image but currently loses the kernel.target metadata.
        vmTools = prev.vmTools.override {
          kernelImage = prev.linuxPackages.kernel.target;
        };
      })
    ];
  };
in {
  system.stateVersion = "25.05";

  imports = [
    inputs.disko.nixosModules.disko
    ../../../profiles/fleet-core.nix
    ../../../profiles/headless.nix
    ../../../profiles/home.nix
    ../../../profiles/pray-for-sd-card.nix
    ../../../profiles/bluefield-hostpf.nix
    ../../../services/buildfarm-slave.nix
    ./vpp-lab.nix
    ./vpp-cnat-lab.nix
    ./ipsec-ikev2-lab.nix
    ./vpp-production-staged.nix
    ./vpp-transition-staged.nix
  ];

  deployment.targetHost = network.primaryIp self;
  deployment.targetUser = "grw";

  sconfig = {
    profile = "server";
    home-manager.enable = false;
  };

  networking = {
    hostName = "bluefield2";
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = true;
    # Keep host metrics on 9100 and allow VPP telemetry only from VictoriaMetrics.
    firewall.allowedTCPPorts = [9100];
    firewall.allowPing = true;
    firewall.extraCommands = ''
      iptables -A nixos-fw -p tcp -s ${trexIp} --dport 9482 -j nixos-fw-accept
    '';
  };

  # This DPU holds the lan address on enamlnxbf17i0 and the fabric address on
  # br-fabric, and lan and fabric deliberately share one L2 domain. With
  # Linux's default weak-host ARP both interfaces answered for BOTH addresses,
  # so peers learned 192.168.23.22 behind br-fabric's MAC and sent LAN traffic
  # to the wrong interface -- which is why this host was reachable from
  # strix-3 (directly attached) but appeared dead from trex, even though port
  # 22 was open the whole time. Same fix as the strix nodes: answer only on
  # the interface owning the target address, and never source an ARP from
  # another interface's address.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.default.arp_ignore" = 1;
    "net.ipv4.conf.all.arp_announce" = 2;
    "net.ipv4.conf.default.arp_announce" = 2;
  };

  # BeeGFS is retired (2026-07-30). mgmtd ran here as the always-on
  # coordinator, but the meta and storage daemons on the Strix nodes were
  # never enabled, so it had been coordinating an empty cluster: clients found
  # no storage targets and mnt-beegfs.mount simply failed. Models are served
  # from trex over NVMe-oF/RDMA instead -- see machines/x86/trex/
  # spdk-models-snapshot.nix and machines/x86/fuckup/nvme-models.nix.
  #
  # The dead per-machine config was deleted on 2026-08-09. modules/beegfs.nix,
  # modules/mounts-beeg.nix, packages/beegfs/ and tests/beegfs.nix are left
  # intact, as is the per-node beegfsDiskSerial/beegfsFsUUID inventory in
  # network.nix, so this can be revived without rediscovering any of it.

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;

    links = {
      "20-bluefield-fabric" = {
        matchConfig.OriginalName = "enp3s0np0";
        linkConfig = {
          MTUBytes = toString network.vlans.fabric.mtu;
          # Live cabling (2026-08-28): HELLAS serial 2606180004 to CRS812
          # qsfp56-1-1. Although the vendor part number says 200G, both ends
          # decode this cable as QSFP28 100GBASE-CR4. The vpp-lab module forces
          # the otherwise ambiguous four-lane mode after networkd applies this
          # baseline; forcing 200G leaves both ends at NO-CARRIER.
          AutoNegotiation = false;
          BitsPerSecond = "100G";
          Duplex = "full";
        };
      };
    };

    networks = {
      "10-bluefield-oob" = {
        matchConfig.MACAddress = oobMac;
        address = [
          (network.cidrOf "lan" self.addresses.lan)
          # Control-plane rescue subnet. This is the DPU's Linux management
          # side, not VPP's data plane -- which is exactly what you want to
          # reach when VPP is the thing that has gone wrong.
          (network.cidrOf "rescue" self.addresses.rescue)
        ];
        dns = [network.dnsIp];
        routes = [
          {
            Gateway = network.routerIp;
            Metric = 1;
          }
        ];
        # The fabric gateway moved from the CRS804 to the CRS812 (2026-08-13),
        # so this static entry has to follow the CRS812's bridge MAC. Pinning
        # the CRS804's old MAC here silently blackholes the DPU's gateway
        # traffic, because nothing ever ARPs to correct it.
        neighbors = [
          {
            Address = network.gatewayIp "fabric";
            LinkLayerAddress = "38:32:7a:14:ff:67";
          }
        ];
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "ipv6";
        };
        linkConfig.RequiredForOnline = "routable";
      };

      # RShim/host-side recovery link. The external host owns
      # 192.168.100.1/30 and the DPU side is 192.168.100.2/30.
      "20-bluefield-tmfifo" = {
        matchConfig.Driver = "virtio_net";
        address = [
          "192.168.100.2/30"
        ];
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
        };
        linkConfig.RequiredForOnline = "no";
      };

    } // (if hostPfMode == "linux-bridge" then {
      # With the eswitch in switchdev mode, host PF traffic surfaces on the
      # pf0hpf representor; bridge it to the uplink so the host's PF reaches
      # the fabric. The DPU's own fabric address lives on the bridge.
      "90-fabric-uplink" = {
        matchConfig.Name = "enp3s0np0";
        networkConfig.Bridge = "br-fabric";
        linkConfig = {
          MTUBytes = toString network.vlans.fabric.mtu;
          RequiredForOnline = "no";
        };
      };

      "90-fabric-hostpf" = {
        matchConfig.Name = "pf0hpf";
        networkConfig.Bridge = "br-fabric";
        linkConfig = {
          MTUBytes = toString network.vlans.fabric.mtu;
          RequiredForOnline = "no";
        };
      };

      "91-br-fabric" = {
        matchConfig.Name = "br-fabric";
        address = [
          (network.cidrOf "fabric" self.addresses.fabric)
        ];
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
        linkConfig = {
          MTUBytes = toString network.vlans.fabric.mtu;
          RequiredForOnline = "no";
        };
      };
    } else {
      "90-bluefield-data-ports" = {
        matchConfig.Name = "enp3s0np0";
        address = [
          (network.cidrOf "fabric" self.addresses.fabric)
        ];
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
        };
        linkConfig = {
          MTUBytes = toString network.vlans.fabric.mtu;
          RequiredForOnline = "no";
        };
      };
    } // lib.optionalAttrs (hostPfMode == "vpp-representor") {
      # Linux retains this representor for VPP's runtime AF_PACKET attachment.
      # It gets no Linux address, bridge, default route, or online requirement.
      "90-fabric-hostpf" = {
        matchConfig.Name = "pf0hpf";
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
        };
        linkConfig = {
          MTUBytes = toString network.vlans.${network.routing.hostPf.network}.mtu;
          RequiredForOnline = "no";
        };
      };
    });

    # NB (2026-08-10): with hostPfMode = off/vpp-representor this bridge is
    # never created, and
    # the fabric address belongs on enp3s0np0 via 90-bluefield-data-ports
    # below. A br-fabric left over from an earlier hostPf = true generation
    # survived here for months -- networkd does not delete netdevs it no
    # longer manages -- holding 192.168.25.22 with a randomly generated MAC
    # and shadowing the intended config. That, plus weak-host ARP, is why this
    # host looked dead from trex while being perfectly healthy. If you ever
    # flip hostPf back on, give this bridge an explicit MACAddress.
    netdevs = lib.optionalAttrs (hostPfMode == "linux-bridge") {
      "90-br-fabric" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br-fabric";
        };
      };
    };
  };

  disko = {
    memSize = 4096;
    imageBuilder = {
      enableBinfmt = true;
      pkgs = imagePkgs;
      kernelPackages = imagePkgs.linuxPackages;
    };

    devices = {
      disk.bluefield2-emmc = {
        device = "/dev/mmcblk0";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "512M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "btrfs";
                mountpoint = "/";
                mountOptions = ["compress=zstd:1" "noatime"];
              };
            };
          };
        };
      };
    };
  };

  boot = {
    kernelPackages = bluefieldKernelPackages;
    kernelParams = [
      "console=hvc0"
      "console=ttyAMA0,115200n8"
      "earlycon=pl011,0x01000000"
    ];
    supportedFilesystems = ["vfat" "btrfs"];

    loader = {
      timeout = 1;
      efi.canTouchEfiVariables = false;
      grub.enable = false;
      systemd-boot = {
        enable = true;
        # Keep the accepted production entry across several attended one-shot
        # experiments. A four-entry limit previously evicted the last
        # known-good entry, including its EFI payloads, before the next test
        # boot had even begun.
        configurationLimit = 8;
        extraFiles."EFI/BOOT/BOOTAA64.EFI" = "${pkgs.systemd}/lib/systemd/boot/efi/systemd-bootaa64.efi";
      };
    };

    initrd = {
      systemd = {
        enable = true;
        emergencyAccess = true;
        network.enable = true;
      };

      availableKernelModules = [
        "dw_mmc"
        "dw_mmc-bluefield"
        "dw_mmc-pltfm"
        "sdhci_acpi"
        "sdhci-of-dwcmshc"
        "mmc_block"
        "mlx5_core"
        "mlxbf_gige"
        "mlxbf-tmfifo"
        "virtio_console"
        "virtio_net"
      ];

      kernelModules = [
        "dw_mmc-bluefield"
        "sdhci_acpi"
        "mmc_block"
      ];
    };

    kernelModules = [
      "mlx5_core"
    ] ++ lib.optionals hostPf [
      # DPDK's mlx5 PMD still requires the Verbs control device.  Loading this
      # before bluefield-switchdev also removes the udev race observed in the
      # first 6.12 DPDK boot ("Verbs device not found"). mlx5_ib pulls in
      # ib_uverbs and ib_core through its module dependencies.
      "mlx5_ib"
    ] ++ [
      "mlxbf_gige"
      "mlxbf-tmfifo"
    ];
  };

  # In EMBEDDED_CPU mode the external host PF only leaves firmware
  # pre-init once the eswitch is enabled (mlx5_eswitch_enable_pf_vf_vports
  # issues the ENABLE_HCA that clears the host PF's initializing bit).
  # Upstream kernels leave the eswitch down in legacy mode with no VFs,
  # so force switchdev at boot.
  systemd.services.bluefield-switchdev = lib.mkIf hostPf {
    description = "Enable eswitch switchdev mode (brings up the external host PF)";
    wantedBy = ["multi-user.target"];
    after = ["systemd-modules-load.service"];
    before = ["vpp.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "5s";
      # A NixOS activation does not replace the running kernel. Refuse to
      # touch switchdev while activating this closure from the incompatible
      # linux_latest generation; the unit will run after reboot into 6.12.
      ExecCondition = pkgs.writeShellScript "bluefield-switchdev-kernel-compatible" ''
        case "$(${pkgs.coreutils}/bin/uname -r)" in
          6.12.*) exit 0 ;;
          *)
            echo "host-PF switchdev requires the firmware-matched 6.12 kernel; reboot first" >&2
            exit 1
            ;;
        esac
      '';
    };
    script = ''
      mode="$(${pkgs.coreutils}/bin/timeout 1 \
        ${pkgs.iproute2}/bin/devlink dev eswitch show \
          pci/${network.ports.bluefield2.vppData.pciAddress} 2>/dev/null)" || mode=""
      case "$mode" in
        *"mode switchdev"*) exit 0 ;;
      esac

      # Enter switchdev before VPP opens the external port: changing mode can
      # recreate its netdev. One bounded attempt is enough for this optional
      # feature; failure never becomes a VPP requirement or a boot retry loop.
      if ! ${pkgs.coreutils}/bin/timeout 3 \
        ${pkgs.iproute2}/bin/devlink dev eswitch set \
          pci/${network.ports.bluefield2.vppData.pciAddress} mode switchdev; then
        echo "BlueField switchdev unavailable; optional host-PF path inactive" >&2
      fi
      exit 0
    '';
  };

  # BSP-style stable name for the host PF representor so networkd can
  # enslave it; the uplink keeps its enp3s0np0 name (phys_port_name p0).
  # FW 24.40.1000 reports the representor's phys_port_name as "c1pf0"
  # (controller 1, PF 0); older firmware used "pf0hpf".
  services.udev.extraRules = lib.mkIf hostPf ''
    SUBSYSTEM=="net", ACTION=="add", ATTR{phys_port_name}=="pf0hpf", NAME="pf0hpf"
    SUBSYSTEM=="net", ACTION=="add", ATTR{phys_port_name}=="c1pf0", NAME="pf0hpf"
  '';

  systemd.services.bluefield-oob-renegotiate = {
    description = "Renegotiate BlueField OOB management PHY";
    after = ["systemd-networkd.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${oobRenegotiate}";
    };
  };

  # The installed VPP 26.06 vpp_prometheus_export faults in
  # stat_segment_connect_r before binding on this AArch64 image. Use the
  # supported vpp_get_stats client in a bounded sidecar instead; it reconnects
  # on every scrape, so VPP restarts do not require an exporter restart.
  users.users.vpp-exporter = {
    isSystemUser = true;
    group = "vpp";
  };
  systemd.services.vpp-prometheus-exporter = {
    description = "Bounded VPP statseg Prometheus exporter";
    after = ["vpp.service"];
    requires = ["vpp.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      User = "vpp-exporter";
      Group = "vpp";
      ExecStart = "${vppPrometheusExporter}/bin/vpp-prometheus-exporter";
      Restart = "always";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = ["AF_UNIX" "AF_INET6" "AF_NETLINK"];
      MemoryMax = "256M";
    };
    environment = {
      VPP_STATS_SOCKET = "/run/vpp/stats.sock";
      VPP_GET_STATS = "${config.services.vpp.package}/bin/vpp_get_stats";
      ETHTOOL = "${pkgs.ethtool}/bin/ethtool";
      VPP_EXPORTER_PORT = "9482";
    };
  };

  system.activationScripts.bluefield-esp-kernel-sync.text = ''
    kernel=${config.system.build.kernel}/${config.boot.kernelPackages.kernel.target}
    initrd=${config.system.build.initialRamdisk}/initrd

    if ${pkgs.util-linux}/bin/mountpoint -q /boot; then
      updated=0

      if ! ${pkgs.diffutils}/bin/cmp -s "$kernel" /boot/Image 2>/dev/null; then
        ${pkgs.coreutils}/bin/cp "$kernel" /boot/Image.new
        ${pkgs.coreutils}/bin/mv -f /boot/Image.new /boot/Image
        updated=1
      fi

      if ! ${pkgs.diffutils}/bin/cmp -s "$initrd" /boot/initramfs 2>/dev/null; then
        ${pkgs.coreutils}/bin/cp "$initrd" /boot/initramfs.new
        ${pkgs.coreutils}/bin/mv -f /boot/initramfs.new /boot/initramfs
        updated=1
      fi

      if [ "$updated" = 1 ]; then
        echo "bluefield-esp-kernel-sync: updated /boot/Image and /boot/initramfs"
      fi
    else
      echo "bluefield-esp-kernel-sync: /boot is not mounted, skipping"
    fi
  '';

  environment.systemPackages = with pkgs; [
    ethtool
    pkgsBuildBuild.ghostty.terminfo
    iproute2
    mlxbf-bootctl
    mstflint
    pciutils
    usbutils
  ];

  services.getty.autologinUser = "root";

  services.earlyoom = {
    enable = true;
    freeMemThreshold = 10;
    freeSwapThreshold = 10;
    enableNotifications = false;
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  nix.settings = {
    build-cores = 2;
    max-jobs = 1;
    http-connections = 4;
  };
}
