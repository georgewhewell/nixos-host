{
  pkgs,
  lib,
  ...
}: {
  /*
  trex: trx90 system

  # fans:
  # CPU_FAN1: AIO Radiator fans
  # CPU_FAN2/WP: Pump
  # CHA_FAN1/WP: 140mm intakes
  # CHA_FAN2/WP: Unsure.. VRAM?
  # CHA_FAN3/WP: Unsure.. exhaust?
  # MOS_FAN1/MOS_FAN2: VRM
  */
  sconfig = {
    profile = "desktop";
    home-manager = {
      enable = true;
      enableVscodeServer = true;
    };
  };

  # RTX 4090
  nixpkgs.config.cudaCapabilities = ["8.9"];

  # 7985WX
  nix.settings.system-features = ["gccarch-znver4" "kvm" "big-parallel"];

  hardware.cpu.amd.ryzen-smu.enable = true;

  boot.kernel.sysctl = {
    "net.core.rmem_default" = 1048576;
    "net.core.wmem_default" = 1048576;
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.core.netdev_max_backlog" = 50000;
    "net.core.netdev_budget" = 1000;
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.ipv4.route.max_size" = 524288;
    "net.ipv4.tcp_fastopen" = "3";
    "net.ipv6.conf.all.forwarding" = true;
    "net.netfilter.nf_conntrack_max" = 131072;
    "net.nf_conntrack_max" = 131072;
  };

  imports = [
    ../../../containers/arr-servers.nix
    ../../../containers/gh-runner-grw.nix

    ../../../profiles/common.nix
    ../../../profiles/headless.nix
    ../../../profiles/home.nix
    ../../../profiles/development.nix
    ../../../profiles/nvidia.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/nas.nix
    ../../../profiles/crypto
    ../../../profiles/logserver.nix

    ../../../services/nginx.nix
    ../../../services/grafana.nix
    ../../../services/jellyfin.nix
    ../../../services/rtorrent.nix
    ../../../services/buildfarm-executor.nix
    ../../../services/buildfarm-slave.nix
    ../../../services/virt/host.nix
  ];

  boot.kernelPackages = pkgs.linuxPackages_latest.extend (final: prev: {
    zfs_2_3 = prev.zfs_2_3.overrideAttrs (oldAttrs: {
      src = pkgs.fetchFromGitHub {
        owner = "openzfs";
        repo = "zfs";
        rev = "master";
        hash = "sha256-ZlrQC1NBZaxquCEu4IHn+5ZnmJi44gmdbCVzrAKabw4=";
      };
      version = "2.3.3-staging";
    });
  });

  deployment = {
    targetHost = "trex.satanic.link";
    targetUser = "grw";
    buildOnTarget = true;
  };

  services.qbittorrent = {
    enable = true;
    openFirewall = true;
  };

  fileSystems."/var/lib/qbittorrent" = {
    device = "pool3d/root/downloads";
    fsType = "zfs";
    options = ["nofail" "sync=disabled"];
  };

  fileSystems."/mnt/models" = {
    device = "pool3d/root/models";
    fsType = "zfs";
    options = ["nofail"];
  };

  system.stateVersion = "24.11";

  boot.supportedFilesystems = ["ext4" "vfat" "xfs" "zfs"];
  boot = {
    kernelModules = [
      "ipmi_devintf"
      "ipmi_si"
    ];
    kernelParams = [
      "amd_iommu=on"
      "pci=realloc=off" # fixes: only 7 of 8 pex downstream work
      "pcie=pcie_bus_perf"
      "pcie_acs_override=downstream"
      "zswap.enabled=1"
      "zswap.compressor=zstd"
      "zswap.max_pool_percent=20"
    ];
    initrd.kernelModules = ["mlx5_core" "lm92"];
    blacklistedKernelModules = ["nouveau" "amdgpu" "i915"];
  };

  environment.systemPackages = with pkgs; [
    tbtools
    pciutils
    fio
    lm_sensors
    # (llama-cpp.override
    #   {
    #     cudaSupport = true;
    #     rpcSupport = true;
    #   })
  ];

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
  ];

  boot.kernel.sysctl."vm.swappiness" = 10;
  boot.kernel.sysctl."vm.page-cluster" = 0;
  boot.kernel.sysctl."vm.max_map_count" = 1048576;

  # swapDevices =
  #   builtins.genList (
  #     i: {device = "/dev/nvme${toString i}n1p1";}
  #   )
  #   8;

  # otherwise bpool bricks
  boot.zfs.requestEncryptionCredentials = false;

  fileSystems."/" = {
    device = "pool3d/root/trex-root";
    fsType = "zfs";
    options = ["noatime"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/37D0-505A";
    fsType = "vfat";
    options = ["iocharset=iso8859-1" "fmask=0022" "dmask=0022"];
  };

  fileSystems."/home/grw" = {
    device = "pool3d/root/grw-home";
    fsType = "zfs";
    options = ["noatime" "nofail"];
  };

  services = {
    fstrim.enable = true;
    fwupd.enable = true;
    hardware = {
      bolt.enable = true;
      openrgb.enable = true;
    };
    iperf3.enable = true;
  };

  networking = {
    hostName = "trex";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    nameservers = ["192.168.23.1"];
    firewall.enable = false;
  };

  services.ollama = {
    enable = true;
    acceleration = "cuda";
    host = "0.0.0.0";
    port = 11434;
  };

  # services.open-webui = {
  #   enable = true;
  #   host = "0.0.0.0";
  #   port = 11111;
  #   openFirewall = true;
  #   environment = {
  #     ANONYMIZED_TELEMETRY = "False";
  #     DO_NOT_TRACK = "True";
  #     SCARF_NO_ANALYTICS = "True";
  #     OLLAMA_API_BASE_URL = "http://127.0.0.1:11434/api";
  #     OLLAMA_BASE_URL = "http://127.0.0.1:11434";
  #   };
  # };
  #
  services.gcp-ddns = {
    enable = true;
    projectId = "domain-owner";
    zoneName = "satanic-link";
    records = [
      {
        name = "*.satanic.link.";
        type = "AAAA";
        ttl = 300;
      }
    ];
    interval = "5m";
  };

  services.nix-serve = {
    enable = true;
  };

  systemd.network = let
    bridgeName = "br0";
  in {
    enable = true;
    wait-online.anyInterface = true;
    links = {
      "20-mlx5" = {
        matchConfig.Driver = "mlx5_core";
        linkConfig = {
          RxBufferSize = 8192;
          TxBufferSize = 8192;
        };
      };
      "20-thunderbolt" = {
        matchConfig.Driver = "thunderbolt-net";
        linkConfig.MACAddressPolicy = "none";
      };
    };
    netdevs = {
      "20-${bridgeName}" = {
        netdevConfig = {
          Kind = "bridge";
          Name = bridgeName;
        };
      };
    };
    networks = {
      "99-ipheth" = {
        matchConfig.Driver = "ipheth";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = true;
          # DNSOverTLS = true;
          # DNSSEC = true;
          IPv6PrivacyExtensions = true;
          # IPv4Forward = true;
          # IgnoreCarrierLoss = true;
        };
        dhcpV4Config = {
          RouteMetric = 99;
          UseDNS = true;
          UseDomains = false;
          SendRelease = true;
        };
        linkConfig.RequiredForOnline = "no";
      };
      "50-usbeth" = {
        matchConfig.Driver = "r8152";
        networkConfig = {
          Bridge = bridgeName;
          ConfigureWithoutCarrier = true;
        };
        linkConfig.RequiredForOnline = "enslaved";
      };
      "20-thunderbolt" = {
        matchConfig.Driver = "thunderbolt-net";
        networkConfig.Bridge = bridgeName;
        linkConfig.RequiredForOnline = "enslaved";
      };
      "10-lan-10g" = {
        matchConfig.Driver = "i40e";
        networkConfig.Bridge = bridgeName;
        linkConfig.RequiredForOnline = "enslaved";
      };
      "10-lan-10g-2" = {
        matchConfig.Driver = "ixgbe";
        networkConfig.Bridge = bridgeName;
        linkConfig.RequiredForOnline = "enslaved";
      };
      "10-lan-25g" = {
        matchConfig.Driver = "mlx5_core";
        networkConfig.Bridge = bridgeName;
        linkConfig.RequiredForOnline = "enslaved";
      };
      "05-${bridgeName}" = {
        matchConfig.Name = bridgeName;
        bridgeConfig = {};
        address = [
          "192.168.23.8/24"
        ];
        routes = [
          {Gateway = "192.168.23.1";}
        ];
        networkConfig = {
          IPv6AcceptRA = true;
          IPv6Forwarding = true;
          IPv4Forwarding = true;
          IPv6PrivacyExtensions = true;
          ConfigureWithoutCarrier = true;
          IgnoreCarrierLoss = true;
        };
        linkConfig.RequiredForOnline = "routable";
      };
    };
  };
}
