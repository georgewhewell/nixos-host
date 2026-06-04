{
  pkgs,
  lib,
  inputs,
  mkSecret,
  config,
  network,
  ...
}: let
  self = network.hosts.trex;
  hellasGatewayCli = inputs.hellas.packages.${pkgs.stdenv.hostPlatform.system}.cli;
in {
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
      uclampMax = 95;
    };
    gcp-ddns = {
      enable = true;
      hostName = true;
    };
  };

  # 7985WX - big parallel builder
  nix.settings = {
    system-features = ["gccarch-znver4" "kvm" "big-parallel" "nixos-test"];
    download-buffer-size = 104857600; # 100 MiB
    http-connections = 64;
    # Sign locally-built store paths with our cache key so `nix copy` to
    # strix-1/strix-2 (which trust this key via modules/nix.nix) is
    # accepted without --no-check-sigs.
    secret-key-files = [config.sops.secrets.nix-cache-key.path];
  };

  boot.kernel.sysctl = {
    # Network buffer defaults
    "net.core.rmem_default" = 1048576;
    "net.core.wmem_default" = 1048576;
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.core.netdev_max_backlog" = 50000;
    "net.core.netdev_budget" = 1000;
    "net.core.somaxconn" = 8192;

    # TCP tuning for 25Gbps
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.ipv4.tcp_rmem" = "4096 1048576 134217728";
    "net.ipv4.tcp_wmem" = "4096 1048576 134217728";
    "net.ipv4.tcp_slow_start_after_idle" = 0;
    "net.ipv4.tcp_mtu_probing" = 1;
    "net.ipv4.tcp_fastopen" = 3;
    "net.ipv4.tcp_tw_reuse" = 1;
    "net.ipv4.tcp_fin_timeout" = 30;
    "net.ipv4.tcp_max_syn_backlog" = 8192;
    "net.ipv4.route.max_size" = 524288;

    # IPv6 and conntrack
    "net.ipv6.conf.all.forwarding" = true;
    "net.netfilter.nf_conntrack_max" = 262144;
    "net.nf_conntrack_max" = 262144;

    # VM tuning
    "vm.swappiness" = 10;
    "vm.page-cluster" = 0;
    "vm.max_map_count" = 1048576;
  };

  services.hellas = {
    enable = true;
    openFirewall = true;
    port = 31145;
    # downloadPolicy = "eager";
    executePolicy = "allow(hf/HuggingFaceTB/SmolLM2-135M-Instruct)";
    graffiti = "trex";
    preloadWeights = [
      "Qwen/Qwen3.5-0.8B"
    ];
    trustedCallerPublicKeys = [
      "03561852f0eda08f4b842cc800cf68845af1286c4881bf826a29fe87439e27eb08"
      "02edec6b26cae32e9cd0bfbb90594066e60d0f9973b001af3ee15752162ab7dd99"
    ];
    fetchCodexResponses = true;
    fetchCodexAuthPath = "/var/lib/hellas/.hellas/codex-auth.json";
    otel = {
      endpoint = "https://jaeger.lsd-ag.ch/v1/traces";
      serviceName = "executor-fuckup";
      sampleRate = 1;
      headers = {
        CF-Access-Client-Id = "312310f4c9c50c2bf9ee7e801d92a9ed.access";
        CF-Access-Client-Secret = "91bcfc62a1b4058b3c82b31560c146d7761b7cb1a507ff68b26d745d0650f6a8";
      };
    };
  };

  systemd.services.hellas-gateway = {
    description = "Hellas HTTP gateway passthrough to local llama.cpp";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target" "llama-cpp.service"];
    wants = ["network-online.target" "llama-cpp.service"];
    environment = {
      HOME = "/var/lib/hellas-gateway";
    };
    serviceConfig = {
      ExecStart = lib.escapeShellArgs [
        "${hellasGatewayCli}/bin/hellas-cli"
        "--identity"
        "/var/lib/hellas-gateway/.hellas/identity"
        "--producer-key-path"
        "/var/lib/hellas-gateway/.hellas/signing-key.secp256k1"
        "gateway"
        "--host"
        (network.primaryIp self)
        "--port"
        "8083"
        "--responses-backend"
        "proxy"
        "--responses-proxy-url"
        "http://127.0.0.1:8081/v1/responses"
        "--responses-proxy-api-key-env"
        "HELLAS_GATEWAY_PROXY_API_KEY"
      ];
      Restart = "on-failure";
      DynamicUser = true;
      StateDirectory = "hellas-gateway";
      WorkingDirectory = "/var/lib/hellas-gateway";
    };
  };

  nix.settings.build-cores = lib.mkDefault 48;
  nix.settings.max-jobs = lib.mkDefault 4;

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd
    common-gpu-amd

    inputs.nix-strix-halo.nixosModules.default
    inputs.nix-strix-halo.nixosModules.benchmark-runner
    inputs.nix-strix-halo.nixosModules.rpc-server

    inputs.hellas.nixosModules.default

    ../../../containers/arr-servers.nix
    # ../../../containers/gh-runner-grw.nix

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
    ../../../services/victoriametrics.nix
    ../../../services/jellyfin.nix
    ../../../services/buildfarm-executor.nix
    ../../../services/hydra-builder-slave.nix
    ../../../services/buildfarm-slave.nix
    ../../../services/virt/host.nix
    ../../../services/virt/vfio.nix
    ../../../services/apple-health-ingester.nix

    ../../../profiles/thunderbolt-bridge.nix
  ];

  deployment = {
    targetHost = network.primaryIp self;
    targetUser = "grw";
    # buildOnTarget = true;
  };

  hardware.cpu.amd.ryzen-smu.enable = true;
  programs.ryzen-monitor-ng.enable = true;

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
    ];
  };

  sops.secrets.hf-token = mkSecret "hf-token" {};
  sops.templates."hellas-env".content = ''
    HF_TOKEN=${config.sops.placeholder."hf-token"}
  '';
  systemd.services.hellas.serviceConfig.EnvironmentFile =
    config.sops.templates."hellas-env".path;

  sops.secrets.qui-session = mkSecret "qui-session" {};
  sops.secrets.mosquitto-password = mkSecret "mosquitto-password" {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  services.qui = {
    enable = true;
    openFirewall = true;
    secretFile = "/run/secrets/qui-session";
    settings = {
      host = "0.0.0.0";
      port = 7476;
    };
  };

  # Ensure qbittorrent waits for bpool media mount
  systemd.services.qbittorrent = {
    bindsTo = ["mnt-Media.mount"];
    after = ["mnt-Media.mount"];
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

  fileSystems."/mnt/victoriametrics" = {
    device = "pool3d/root/victoriametrics";
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
    cpuFreqGovernor = "schedutil";
  };

  services.max-perf = {
    enable = true;
    description = "trex IPMI fan full-speed mode";
    activeScript = ''
      normalize_bytes() {
        ${pkgs.coreutils}/bin/tr -s '[:space:]' ' ' \
          | ${pkgs.gnused}/bin/sed 's/^ //; s/ $//' \
          | ${pkgs.coreutils}/bin/tr '[:lower:]' '[:upper:]'
      }

      validate_hex_bytes() {
        expected_count="$1"
        shift

        count=0
        for byte in "$@"; do
          case "$byte" in
            [0-9A-F][0-9A-F]) ;;
            *)
              echo "max-perf: invalid IPMI byte '$byte'" >&2
              exit 1
              ;;
          esac
          count=$((count + 1))
        done

        if [ "$count" -ne "$expected_count" ]; then
          echo "max-perf: expected $expected_count IPMI bytes, got $count" >&2
          exit 1
        fi
      }

      # ASRock Rack AST2600 OEM fan control:
      # - read mode: 0x3a 0xd0 0x12
      # - set mode:  0x3a 0xd0 0x11 <16 bytes>
      # - read duty: 0x3a 0xd0 0x0f
      # - set duty:  0x3a 0xd0 0x0e <16 bytes>
      raw_mode="$(${pkgs.ipmitool}/bin/ipmitool -I open raw 0x3a 0xd0 0x12 | normalize_bytes)"
      raw_duty="$(${pkgs.ipmitool}/bin/ipmitool -I open raw 0x3a 0xd0 0x0f | normalize_bytes)"

      set -- $raw_mode
      validate_hex_bytes 16 "$@"
      restore_mode_cmd="${pkgs.ipmitool}/bin/ipmitool -I open raw 0x3a 0xd0 0x11"
      for byte in "$@"; do
        restore_mode_cmd="$restore_mode_cmd 0x$byte"
      done

      set -- $raw_duty
      validate_hex_bytes 16 "$@"
      restore_duty_cmd="${pkgs.ipmitool}/bin/ipmitool -I open raw 0x3a 0xd0 0x0e"
      for byte in "$@"; do
        restore_duty_cmd="$restore_duty_cmd 0x$byte"
      done

      # Restore duty first, then mode (tested on trex).
      ${pkgs.coreutils}/bin/printf '%s || true\n' "$restore_duty_cmd" >> "$MAX_PERF_RESTORE_SCRIPT"
      ${pkgs.coreutils}/bin/printf '%s || true\n' "$restore_mode_cmd" >> "$MAX_PERF_RESTORE_SCRIPT"

      # 0x02 = manual mode for each fan entry (16 entries), then 100%% duty (0x64).
      ${pkgs.ipmitool}/bin/ipmitool -I open raw 0x3a 0xd0 0x11 \
        0x02 0x02 0x02 0x02 0x02 0x02 0x02 0x02 \
        0x02 0x02 0x02 0x02 0x02 0x02 0x02 0x02 >/dev/null
      ${pkgs.ipmitool}/bin/ipmitool -I open raw 0x3a 0xd0 0x0e \
        0x64 0x64 0x64 0x64 0x64 0x64 0x64 0x64 \
        0x64 0x64 0x64 0x64 0x64 0x64 0x64 0x64 >/dev/null
    '';
    mqtt = {
      enable = true;
      host = network.routerIp;
      username = "rw";
      passwordFile = config.sops.secrets.mosquitto-password.path;
    };
  };

  systemd.services.max-perf-mqtt = {
    after = ["sops-install-secrets.service"];
    wants = ["sops-install-secrets.service"];
  };

  # L2ARC tuning for bpool Optane cache - no write rate limit
  boot.extraModprobeConfig = ''
    options zfs l2arc_write_max=9223372036854775807 l2arc_write_boost=9223372036854775807
  '';

  boot = {
    kernelModules = [
      "ipmi_devintf"
      "ipmi_si"
    ];
    kernelParams = [
      "amd_pstate=passive"
      # "hugepages=40960" # 80GB of hugepages
      "transparent_hugepages=madvise"
      # amd_iommu handled by VFIO config (services/virt/vfio.nix)
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

  # SR-IOV setup for Mellanox ConnectX-4 with switchdev mode
  # ConnectX-4 requires reset cycle: destroy VFs → legacy → switchdev → create VFs
  # (firmware-level ESWITCH_MODE not available on CX4)
  systemd.services.sriov-init = {
    description = "Configure Mellanox SR-IOV with switchdev mode";
    wantedBy = ["network-pre.target"];
    before = ["network-pre.target"];
    after = ["sys-subsystem-net-devices-enp172s0np0.device"];
    bindsTo = ["sys-subsystem-net-devices-enp172s0np0.device"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [pkgs.iproute2 pkgs.ethtool];
    script = ''
      set -e
      PCI_DEV="pci/0000:ac:00.0"
      VF_COUNT=8
      COMBINED_CHANNELS=32

      # Destroy any existing VFs first
      echo 0 > /sys/class/net/enp172s0np0/device/sriov_numvfs || true
      sleep 1

      # Reset to legacy mode (ensures clean eswitch state)
      devlink dev eswitch set $PCI_DEV mode legacy || true
      sleep 1

      # Set combined channels before switchdev mode (must be done in legacy mode)
      echo "Setting combined channels to $COMBINED_CHANNELS"
      ethtool -L enp172s0np0 combined $COMBINED_CHANNELS || true

      # Set switchdev mode
      devlink dev eswitch set $PCI_DEV mode switchdev
      sleep 2

      # Create VFs (now works because eswitch is properly initialized)
      echo $VF_COUNT > /sys/class/net/enp172s0np0/device/sriov_numvfs

      echo "SR-IOV initialized: $VF_COUNT VFs in switchdev mode with $COMBINED_CHANNELS channels"
    '';
  };

  # OVS for Mellanox switchdev mode
  virtualisation.vswitch.enable = true;

  networking.vswitches.ovs-mlx = {
    interfaces = {
      # Uplink (PF)
      enp172s0np0 = {};
      # VF representors
      enp172s0r0 = {};
      enp172s0r1 = {};
      enp172s0r2 = {};
      enp172s0r3 = {};
      enp172s0r4 = {};
      enp172s0r5 = {};
      enp172s0r6 = {};
      enp172s0r7 = {};

      # i40e
      enp11s0f0np0 = {};
      enp11s0f1np1 = {};

      # Internal port for host
      ovs-host = {
        type = "internal";
      };
    };
  };

  # Set jumbo MTU on OVS internal port (must be done via ovs-vsctl)
  systemd.services.ovs-host-mtu = {
    description = "Set OVS ovs-host interface MTU to 9000";
    after = ["ovsdb-server.service" "ovs-vswitchd.service" "ovs-mlx-netdev.service"];
    requires = ["ovs-vswitchd.service" "ovs-mlx-netdev.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Wait for interface to appear in OVS (max 30 seconds)
      for i in $(seq 1 30); do
        if ${pkgs.openvswitch}/bin/ovs-vsctl list interface ovs-host >/dev/null 2>&1; then
          ${pkgs.openvswitch}/bin/ovs-vsctl set interface ovs-host mtu_request=9000
          echo "Set ovs-host MTU to 9000"
          exit 0
        fi
        echo "Waiting for ovs-host interface... ($i/30)"
        sleep 1
      done
      echo "ERROR: ovs-host interface not found after 30 seconds"
      exit 1
    '';
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
  services.avahi.allowInterfaces = lib.mkForce ["ovs-host" "thunderbolt0" "thunderbolt1"];
  profiles.thunderbolt-bridge.bridgeThunderboltNet = false;

  # environment.systemPackages = with pkgs; [
  #   tbtools
  #   pciutils
  #   fio
  #   lm_sensors
  #   ryzenadj

  #   smartmontools
  #   geekbench_6
  #   passmark-performancetest

  #   llamacpp-rocm
  # ];

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "x86_64-windows"
  ];

  swapDevices = [
    {device = "/dev/disk/by-uuid/c4052b76-2ab1-4715-b55d-07b0720d58cc";}
    {device = "/dev/disk/by-uuid/30927806-c236-42dc-a198-462b757fd80f";}
    {device = "/dev/disk/by-uuid/74122086-e876-4846-803f-62147dd54895";}
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
    device = "/dev/disk/by-uuid/FA84-F420";
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
    fsType = "none";
    options = ["bind"];
  };

  services = {
    fstrim.enable = true;
    fwupd.enable = true;
    hardware.openrgb.enable = true;
    iperf3.enable = true;

    # ZFS snapshot management - short retention on source
    sanoid = let
      excluded = {
        autosnap = false;
        hourly = 0;
        daily = 0;
        weekly = 0;
        monthly = 0;
      };
    in {
      enable = true;
      interval = "hourly";
      datasets."pool3d" = {
        recursive = true;
        autosnap = true;
        hourly = 24;
        daily = 7;
        weekly = 0;
        monthly = 0;
      };
      datasets."pool3d/root/tari" = excluded;
      datasets."pool3d/root/monero" = excluded;
    };

    # ZFS replication to fuckup
    syncoid = let
      excludedDatasets = ["tari" "monero"];
    in {
      enable = true;
      interval = "hourly";
      sshKey = "/var/lib/syncoid/.ssh/id_ed25519";
      commands."pool3d-to-archive" = {
        source = "pool3d";
        target = "root@fuckup:archive/pool3d";
        recursive = true;
        sendOptions = "w";
        extraArgs = lib.concatMap (d: ["--exclude" d]) excludedDatasets;
      };
    };
  };

  networking = {
    hostName = "trex";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    nameservers = [network.routerIp];
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
        8083 # Hellas gateway
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

  services.open-webui = {
    enable = true;
    host = network.primaryIp self;
    port = 11111;
    openFirewall = true;
    environment = {
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
      ENABLE_OLLAMA_API = "False";
      ENABLE_OPENAI_API = "True";
      OPENAI_API_BASE_URL = "http://127.0.0.1:8081/v1";
      OPENAI_API_KEY = "sk-no-key-required";
    };
  };

  # llama.cpp HTTP server on the Navi 10 dGPU. Uses the Vulkan
  # backend (RADV) because head-to-head bench on Qwen2.5-7B Q4_K_M
  # showed it ~1.5x faster than nixpkgs ROCm on gfx1010 (Navi 10 is at
  # the edge of supported ROCm territory; no matrix cores). TheRock
  # SDK isn't an option here — it's gfx1151-only in nix-strix-halo.
  #
  # DynamicUser=true (from the upstream module) plus SupplementaryGroups
  # is what gets the unit access to /dev/dri/renderD* for Vulkan and
  # /dev/kfd for ROCm — the runtime won't enumerate the GPU otherwise.
  services.llama-cpp = {
    enable = true;
    package = inputs.nix-strix-halo.packages.x86_64-linux.llama-cpp-master-vulkan;
    host = "0.0.0.0";
    # 8080 is taken by qBittorrent's webui above; use 8081 for llama-server.
    port = 8081;
    openFirewall = true;
    modelsDir = "/mnt/models";
    extraFlags = [
      "-ngl"
      "999"
      "--flash-attn"
      "on"
    ];
  };
  systemd.services.llama-cpp.serviceConfig.SupplementaryGroups = ["render" "video"];

  # ROCm variant kept side-by-side so we can re-run `llama-bench` to
  # compare backends after upstream changes. Not exposed as a service.
  environment.systemPackages = [
    inputs.nix-strix-halo.packages.x86_64-linux.llama-cpp-master-rocm
  ];

  services.nix-serve = {
    enable = true;
    secretKeyFile = config.sops.secrets.nix-cache-key.path;
  };

  sops.secrets.nix-cache-key = mkSecret "nix-cache-key" {};

  # # Enable rpcbind for NFS
  # services.rpcbind.enable = true;

  # # NFS server configuration with multiple authentication methods
  # services.nfs = {
  #   settings = {
  #     nfsd.vers3 = lib.mkForce true; # Enable NFSv3 as fallback
  #     nfsd."vers4.0" = lib.mkForce true; # Enable NFSv4.0 for macOS compatibility
  #     nfsd."vers4.1" = lib.mkForce true;
  #     nfsd."vers4.2" = lib.mkForce true;
  #   };
  #   server = {
  #     enable = true;
  #     # Enable both NFSv3 and NFSv4
  #     lockdPort = 4001;
  #     mountdPort = 4002;
  #     statdPort = 4000;
  #     exports = ''
  #       /export/grw *(rw,sync,nohide,no_subtree_check,insecure,all_squash,anonuid=1000,anongid=100,sec=sys)
  #     '';
  #   };
  # };

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
    bridgeName = "br0.lan";
  in {
    enable = true;
    wait-online.anyInterface = true;
    links = {
      # PF: buffer settings
      "20-mlx5-pf" = {
        matchConfig.OriginalName = "enp172s0np0";
        linkConfig = {
          RxBufferSize = 8192;
          TxBufferSize = 8192;
        };
      };
    };
    netdevs = {
      "20-${bridgeName}" = {
        netdevConfig = {
          Kind = "bridge";
          Name = bridgeName;
        };
        bridgeConfig = {
          STP = true;
        };
      };
    };
    networks = {
      # Mellanox PF (100G): bring up for OVS with jumbo MTU
      "10-lan-100g" = {
        matchConfig.Name = "enp172s0np0";
        linkConfig = {
          ActivationPolicy = "up";
          RequiredForOnline = "no";
          MTUBytes = "9000";
        };
      };
      # VFs: don't configure (will be passed to containers)
      "10-mlx5-vf" = {
        matchConfig.Name = "enp172s0v*";
        linkConfig.Unmanaged = "yes";
      };
      # VF representors: bring up for OVS
      "10-mlx5-rep" = {
        matchConfig.Name = "enp172s0r*";
        linkConfig = {
          ActivationPolicy = "up";
          RequiredForOnline = "no";
        };
      };
      # OVS internal port for host connectivity
      "10-ovs-host" = {
        matchConfig.Name = "ovs-host";
        address = [(network.cidrOf "lan" self.addresses.lan)];
        routes = [{Gateway = network.routerIp;}];
        networkConfig = {
          DNS = network.routerIp;
        };
        # Only autoconfigure SLAAC from our ISP's delegated /64. Rogue RAs from
        # other devices on the LAN (e.g. Apple devices acting as Tailscale
        # subnet routers) advertise ULA prefixes that briefly get autoconfigured
        # and then trigger ICMPv6 "advertised our address" dmesg spam when the
        # host's own NAs are reflected back through OVS/the Mellanox eswitch.
        ipv6AcceptRAConfig = {
          PrefixAllowList = "2a02:168:58b4::/64";
        };
        linkConfig.RequiredForOnline = "routable";
      };
      # br0.lan for non-Mellanox interfaces (Intel, thunderbolt, USB) - no IP, just L2
      "05-${bridgeName}" = {
        matchConfig.Name = bridgeName;
        bridgeConfig = {};
        networkConfig = {
          ConfigureWithoutCarrier = true;
          IgnoreCarrierLoss = true;
        };
        linkConfig.RequiredForOnline = "no";
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
