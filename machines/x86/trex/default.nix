{
  pkgs,
  lib,
  inputs,
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
    xmrig = {
      enable = true;
      package = pkgs.xmrig-zen4;
    };
    gcp-ddns = {
      enable = true;
      hostName = true;
    };
  };

  # 7985WX
  nix.settings.system-features = ["gccarch-znver4" "kvm" "big-parallel" "nixos-test"];
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
    "vm.swappiness" = 10;
    "vm.page-cluster" = 0;
    "vm.max_map_count" = 1048576;
  };

  nix.settings.build-cores = lib.mkDefault 48;
  nix.settings.max-jobs = lib.mkDefault 12;

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd
    common-gpu-amd
    ../../../containers/arr-servers.nix
    ../../../containers/gh-runner-grw.nix

    ../../../profiles/common.nix
    ../../../profiles/headless.nix
    ../../../profiles/home.nix
    ../../../profiles/development.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/zfs.nix
    ../../../profiles/nas.nix
    ../../../profiles/crypto
    ../../../profiles/logserver.nix
    ../../../profiles/radeon.nix

    ../../../services/nginx.nix
    ../../../services/grafana.nix
    ../../../services/jellyfin.nix
    # ../../../services/rtorrent.nix
    ../../../services/buildfarm-executor.nix
    ../../../services/buildfarm-slave.nix
    ../../../services/virt/host.nix
    ../../../services/virt/vfio.nix
  ];

  deployment = {
    targetHost = "trex.satanic.link";
    targetUser = "grw";
    buildOnTarget = true;
  };

  services.qbittorrent = {
    enable = true;
    # Use the profile root at /var/lib/qbittorrent so qBittorrent
    # places config under /var/lib/qbittorrent/qBittorrent/config
    # and data under /var/lib/qbittorrent/data (avoids double-nesting).
    profileDir = "/var/lib/qbittorrent";
    webuiPort = 8080;
    torrentingPort = 17026;
    openFirewall = true;
  };

  fileSystems."/var/lib/qbittorrent" = {
    device = "pool3d/root/downloads";
    fsType = "zfs";
    options = ["nofail"];
  };

  fileSystems."/mnt/models" = {
    device = "pool3d/root/models";
    fsType = "zfs";
    options = ["nofail"];
  };

  system.stateVersion = "24.11";

  boot.kernel.sysctl = {
    "vm.nr_hugepages_1gb" = 1;
  };

  fileSystems."/dev/hugepages1G" = {
    device = "hugetlbfs";
    fsType = "hugetlbfs";
    options = ["pagesize=1G" "size=1G" "mode=1777"];
  };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "performance";
  };

  boot = {
    kernelModules = [
      "ipmi_devintf"
      "ipmi_si"
    ];
    kernelParams = [
      # "hugepages=40960" # 80GB of hugepages
      "transparent_hugepages=madvise"
      "amd_iommu=off"
      "pci=realloc=off" # fixes: only 7 of 8 pex downstream work
      "pcie=pcie_bus_perf"
      "pcie_acs_override=downstream"
      "zswap.enabled=1"
      "zswap.compressor=zstd"
      "zswap.max_pool_percent=20"
    ];
    initrd.kernelModules = ["mlx5_core" "lm92"];
    blacklistedKernelModules = ["nouveau" "i915"];
  };

  # boot.kernel.sysctl = {
  # "vm.nr_hugepages" = 40960;
  # };

  # Ensure hugepages are mounted
  # systemd.mounts = [{
  #   what = "hugetlbfs";
  #   where = "/dev/hugepages";
  #   type = "hugetlbfs";
  #   options = "mode=1770,gid=kvm";
  #   wantedBy = [ "multi-user.target" ];
  # }];

  environment.systemPackages = with pkgs; [
    tbtools
    pciutils
    fio
    lm_sensors

    smartmontools
    geekbench_6
    passmark-performancetest

    (llama-cpp.override
      {
        cudaSupport = false;
        rocmSupport = false;
        rpcSupport = true;
      })
  ];

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "x86_64-windows"
  ];

  swapDevices = [
    {device = "/dev/disk/by-uuid/c4052b76-2ab1-4715-b55d-07b0720d58cc";}
    {device = "/dev/disk/by-uuid/30927806-c236-42dc-a198-462b757fd80f";}
    {device = "/dev/disk/by-uuid/74122086-e876-4846-803f-62147dd54895";}
    {device = "/dev/disk/by-uuid/ec05a540-9c85-430d-be23-07392ef1e483";}
    {device = "/dev/disk/by-uuid/3abe0f94-1b4b-40bf-8023-9cedaa4e8485";}
    {device = "/dev/disk/by-uuid/7f89d211-da19-4b27-864b-aa16761af3b5";}
    {device = "/dev/disk/by-uuid/84df5a65-7f52-4350-84f2-9c38fb4747bb";}
    {device = "/dev/disk/by-uuid/9c8d8671-759b-48ba-a4e9-92cc3c20f8cb";}
    {device = "/dev/disk/by-uuid/d8aac565-6df0-42be-bb6f-d8f42cb8cd81";}
  ];

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

  # Bind mount for NFSv4 export
  fileSystems."/export/grw" = {
    device = "/home/grw";
    options = ["bind"];
  };

  # services = {
  #   fstrim.enable = true;
  #   fwupd.enable = true;
  #   hardware = {
  #     bolt.enable = true;
  #     openrgb.enable = true;
  #   };
  #   iperf3.enable = true;
  # };

  networking = {
    hostName = "trex";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    nameservers = ["192.168.23.1"];
    firewall = {
      enable = false;
      allowedTCPPorts = [
        2049 # NFS
        111 # rpcbind/portmapper
        88 # Kerberos authentication
        749 # Kerberos administration
        4000 # statd
        4001 # lockd
        4002 # mountd
        17026 # qbittorrent
        18089 # monerod
        20048 # NFSv4 callback
      ];
      allowedUDPPorts = [
        2049 # NFS
        111 # rpcbind/portmapper
        88 # Kerberos authentication
        4000 # statd
        4001 # lockd
        4002 # mountd
        17026 # qbittorrent
        18089 # monerod
        20048 # NFSv4 callback
      ];
    };
  };

  # services.ollama = {
  #   enable = true;
  #   acceleration = "cuda";
  #   host = "0.0.0.0";
  #   port = 11434;
  # };

  services.open-webui = {
    enable = false;
    host = "192.168.23.8";
    port = 11111;
    openFirewall = true;
    environment = {
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
      OLLAMA_API_BASE_URL = "http://127.0.0.1:11434/api";
      OLLAMA_BASE_URL = "http://127.0.0.1:11434";
    };
  };

  services.nix-serve = {
    enable = true;
  };

  # NFS server configuration with multiple authentication methods
  services.nfs = {
    settings = {
      nfsd.vers3 = lib.mkForce true; # Enable NFSv3 as fallback
      nfsd."vers4.0" = lib.mkForce true; # Enable NFSv4.0 for macOS compatibility
      nfsd."vers4.1" = lib.mkForce true;
      nfsd."vers4.2" = lib.mkForce true;
    };
    server = {
      enable = true;
      # Enable both NFSv3 and NFSv4
      lockdPort = 4001;
      mountdPort = 4002;
      statdPort = 4000;
      exports = ''
        /export/grw *(rw,sync,nohide,no_subtree_check,insecure,all_squash,anonuid=1000,anongid=100,sec=sys)
      '';
    };
  };

  # Enable rpcbind for NFS
  services.rpcbind.enable = true;

  # programs.corefreq.enable = true;

  # Configure NFSv4 ID mapping
  # services.nfs.idmapd.settings = {
  #   General = {
  #     Domain = "satanic.link";
  #   };
  #   Mapping = {
  #     Nobody-User = "nobody";
  #     Nobody-Group = "nogroup";
  #   };
  # };

  # # Enable Kerberos for NFS authentication
  # security.krb5 = {
  #   enable = true;
  #   settings = {
  #     libdefaults = {
  #       default_realm = "SATANIC.LINK";
  #       dns_lookup_realm = false;
  #       dns_lookup_kdc = false;
  #     };
  #     realms = {
  #       "SATANIC.LINK" = {
  #         kdc = "trex.satanic.link";
  #         admin_server = "trex.satanic.link";
  #       };
  #     };
  #     domain_realm = {
  #       ".satanic.link" = "SATANIC.LINK";
  #       "satanic.link" = "SATANIC.LINK";
  #     };
  #   };
  # };

  # # Enable Kerberos KDC
  # services.kerberos_server = {
  #   enable = true;
  #   settings.realms = {
  #     "SATANIC.LINK" = {
  #       acl = [
  #         {
  #           principal = "admin";
  #           access = ["add" "cpw" "delete" "get" "list" "modify"];
  #         }
  #       ];
  #     };
  #   };
  # };

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

  # Create needed directories (no-ops if already exist)
  systemd.tmpfiles.rules = [
    # qBittorrent profile + incomplete on SSD (pool3d)
    "d /var/lib/qbittorrent 0775 qbittorrent qbittorrent -"
    "d /var/lib/qbittorrent/incomplete 0775 qbittorrent qbittorrent -"

    # Completed download roots on HDD (bpool)
    "d /mnt/Media/downloads 0777 - - -"
    "d /mnt/Media/downloads/sonarr 0777 - - -"
    "d /mnt/Media/downloads/radarr 0777 - - -"
  ];
}
