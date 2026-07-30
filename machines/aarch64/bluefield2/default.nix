{
  config,
  pkgs,
  lib,
  inputs,
  network,
  ...
}: let
  self = network.hosts.bluefield2;
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
  };
  # Set when the card sits in a PCIe host whose PF should reach the fabric
  # through the DPU — enables the bluefield-switchdev service, the pf0hpf
  # representor rename, and the br-fabric bridge below. Off = standalone:
  # the DPU owns the port directly and any slot it sits in is power-only.
  hostPf = false;
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
    ../../../services/buildfarm-slave.nix
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
  };

  # BeeGFS is retired (2026-07-30). mgmtd ran here as the always-on
  # coordinator, but the meta and storage daemons on the Strix nodes were
  # commented out, so it had been coordinating an empty cluster: clients found
  # no storage targets and mnt-beegfs.mount simply failed. Models are served
  # from trex over NVMe-oF/RDMA instead -- see machines/x86/trex/
  # spdk-models-snapshot.nix and machines/x86/fuckup/nvme-models.nix.
  #
  # modules/beegfs.nix, modules/mounts-beeg.nix, packages/beegfs/ and
  # tests/beegfs.nix are all left intact, as is the per-node
  # beegfsDiskSerial/beegfsFsUUID inventory in network.nix, so this can be
  # revived without rediscovering any of it.

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;

    links = {
      "20-bluefield-fabric" = {
        matchConfig.OriginalName = "enp3s0np0";
        linkConfig = {
          MTUBytes = toString network.vlans.fabric.mtu;
          # The second four-lane branch of the CRS804 cage-1 2x200G DAC is
          # forced to 200G CR4. CRS804 breakout links require matching forced
          # modes at both ends rather than autonegotiation.
          AutoNegotiation = false;
          BitsPerSecond = "200G";
          Duplex = "full";
        };
      };
    };

    networks = {
      "10-bluefield-oob" = {
        matchConfig.MACAddress = oobMac;
        address = [
          (network.cidrOf "lan" self.addresses.lan)
        ];
        dns = [network.routerIp];
        routes = [
          {
            Gateway = network.routerIp;
            Metric = 1;
          }
        ];
        neighbors = [
          {
            Address = network.gatewayIp "fabric";
            LinkLayerAddress = "d0:ea:11:d1:9d:85";
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

    } // (if hostPf then {
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
    });

    netdevs = lib.optionalAttrs hostPf {
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
        configurationLimit = 4;
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
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for _ in $(${pkgs.coreutils}/bin/seq 1 30); do
        mode="$(${pkgs.iproute2}/bin/devlink dev eswitch show pci/0000:03:00.0 2>/dev/null)" || mode=""
        case "$mode" in
          *"mode switchdev"*) exit 0 ;;
        esac
        if ${pkgs.iproute2}/bin/devlink dev eswitch set pci/0000:03:00.0 mode switchdev; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 2
      done
      echo "failed to enable switchdev on pci/0000:03:00.0" >&2
      exit 1
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
