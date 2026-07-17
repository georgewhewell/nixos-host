index: { pkgs
       , lib
       , inputs
       , mkSecret
       , config
       , network
       , ...
       }:
let
  hostName = "strix-${toString index}";
  self = network.hosts.${hostName};
  # Diskless hosts boot via PXE/iPXE and run from trex's NFS store. The
  # flag lives in network.nix so the router (DHCP/TFTP) and trex
  # (exports/boot files) stay in sync with the machine config.
  netboot = self.netboot or false;
  singleDisk = builtins.elem index [ 3 4 ];
  enableUsb4Rdma = builtins.elem index [ 1 2 3 4 ];
  enableCx5Fabric = builtins.elem index [ 1 2 3 4 ];
  enableSharedCx5 = enableCx5Fabric;
  enableVllmTp2 = builtins.elem index [ 3 4 ];
  # The shared ConnectX-5 ports attach to the Ethernet-only CRS804.  Keep the
  # separate flag so the old IPoIB/OpenSM experiment cannot silently return.
  enableSharedIb = false;
  enableUsb4Tcp = false;
  reserveThunderbolt0ForMac = false;
  ryzenAdjLimits =
    if builtins.elem index [ 1 2 ]
    then {
      stapm = 132000;
      fast = 176000;
      slow = 154000;
      apuSlow = 154000;
    }
    else {
      # Strix 3/4 currently clamp package requests to these values.
      stapm = 120000;
      fast = 160000;
      slow = 140000;
      apuSlow = 140000;
    };
  tbvPackages = inputs.thunderbolt-ibverbs-kernel.packages.${pkgs.stdenv.hostPlatform.system} or { };
  tbvHipGdaProbes = tbvPackages."tbv-hip-gda-probes" or null;
  isSecondCx5Host = builtins.elem index [ 2 4 ];
  expectedCx5PortOwner = if isSecondCx5Host then "True(1)" else "False(0)";
  expectedCx5RoceControl = if isSecondCx5Host then "ROCE_ENABLE(2)" else "DEVICE_DEFAULT(0)";
  opensmVirtualizedConfig = pkgs.writeText "opensm-virtualized.conf" ''
    virt_enabled 2
  '';
  vllmPythonInputs = [
    pkgs.vllm-rocm
    pkgs.python312Packages.ray
  ]
  ++ lib.optional (pkgs ? vllm-rust-tool-parser) pkgs.vllm-rust-tool-parser;
  vllmPythonPackages = pkgs.symlinkJoin {
    name = "vllm-strix-python-packages";
    paths = vllmPythonInputs;
  };
  # A symlinkJoin contains the top-level packages but does not assemble their
  # propagated Python dependencies into one site-packages directory.  Build
  # PYTHONPATH from the full closure so interactive and benchmark entrypoints
  # see ROCm Torch and the rest of vLLM's runtime dependencies.
  vllmPythonPath = pkgs.python312Packages.makePythonPath vllmPythonInputs;
  vllmRayConfig = pkgs.writeTextDir "ray_non_carry_over_env_vars.json" (builtins.toJSON [
    # These are deliberately different on alternating halves of each shared
    # multi-host CX5.  Ray workers inherit the correct node-local values from
    # `ray start`; do not replace them with the driver's port-0 selection.
    "GLOO_SOCKET_IFNAME"
    "NCCL_IB_HCA"
    "NCCL_SOCKET_IFNAME"
    "VLLM_HOST_IP"
  ]);
  mkVllmEntrypoint = name: target: pkgs.writeShellScriptBin name ''
    export PYTHONNOUSERSITE=true
    export VLLM_CONFIG_ROOT=${lib.escapeShellArg vllmRayConfig}
    if [[ -n "''${PYTHONPATH:-}" ]]; then
      export PYTHONPATH=${lib.escapeShellArg vllmPythonPath}:"$PYTHONPATH"
    else
      export PYTHONPATH=${lib.escapeShellArg vllmPythonPath}
    fi
    if [[ -n "''${LD_LIBRARY_PATH:-}" ]]; then
      export LD_LIBRARY_PATH=${lib.escapeShellArg "${pkgs.rdma-core-usb4}/lib"}:"$LD_LIBRARY_PATH"
    else
      export LD_LIBRARY_PATH=${lib.escapeShellArg "${pkgs.rdma-core-usb4}/lib"}
    fi
    exec ${lib.escapeShellArg target} "$@"
  '';
  vllmEntrypoints = pkgs.symlinkJoin {
    name = "vllm-strix-entrypoints";
    paths = [
      # Bypass vllm-rocm's generated PATH wrapper here. It puts the unpatched
      # PyPI Ninja wheel ahead of Nix's Ninja, and that binary expects /bin/sh.
      (mkVllmEntrypoint "vllm" "${pkgs.vllm-rocm}/bin/.vllm-wrapped")
      (mkVllmEntrypoint "ray" "${pkgs.python312Packages.ray}/bin/ray")
      (mkVllmEntrypoint "python" "${pkgs.python312}/bin/python")
      (mkVllmEntrypoint "vllm-python" "${pkgs.python312}/bin/python")
    ];
  };
  vllmStrix = pkgs.symlinkJoin {
    name = "vllm-strix-rocm-ray-env";
    paths = [
      vllmEntrypoints
      vllmPythonPackages
      pkgs.ninja
      pkgs.rccl-usb4-topology
    ];
  };
  useCx5Port1 = builtins.elem index [ 1 3 ];
  vllmFabricInterface = if useCx5Port1 then "enp195s0f1np1" else "enp195s0f0np0";
  vllmFabricHca = if useCx5Port1 then "mlx5_1" else "mlx5_0";
  vllmHostIp =
    if enableCx5Fabric
    then network.ipOf "fabric" self.addresses.fabric
    else "10.5.0.${toString index}";
  vllmMasterIp = network.ipOf "fabric" network.hosts.strix-4.addresses.fabric;
  # Resolve the shared, pre-staged snapshot directly. Having every distributed
  # rank resolve the Hub model ID against the same NFS cache can deadlock in
  # huggingface_hub's per-blob file lock during simultaneous startup.
  vllmSmokeModel = "/models/.cache/huggingface/hub/models--Qwen--Qwen3-0.6B/snapshots/c1899de289a04d12100db370d81485cdf75e47ca";
  # AITER and Triton compile a small set of device-specific extensions on
  # first use. systemd's default PATH does not contain `c++`, which otherwise
  # makes startup fail with opaque Ninja or Triton launcher errors.
  vllmServicePath = [
    pkgs.bash
    pkgs.binutils
    pkgs.coreutils
    pkgs.gcc
    pkgs.gnumake
    pkgs.ninja
    pkgs.therock-rocm
  ];
  vllmServiceEnvironment = cacheName: [
    "VLLM_TARGET_DEVICE=rocm"
    "VLLM_HOST_IP=${vllmHostIp}"
    # Model acquisition belongs to trex. Keep compute nodes strictly offline
    # with respect to the Hub and consume the read-only snapshot.
    "HF_HUB_OFFLINE=1"
    "TRANSFORMERS_OFFLINE=1"
    "HF_HUB_DISABLE_TELEMETRY=1"
    "AITER_JIT_DIR=/var/cache/${cacheName}/aiter"
    "HSA_OVERRIDE_GFX_VERSION=11.5.1"
    "HSA_ENABLE_DMABUF=0"
    "HIP_VISIBLE_DEVICES=0"
    # The in-cluster driver uses Ray's v1 executor. Ray-v2 currently stalls in
    # its cross-process shared-memory broadcaster on this four-node ROCm
    # topology. Keep compiled DAG enabled, but let Ray assign HIP device 0 to
    # each actor; suppressing that assignment leaves its accelerator context
    # with an empty visible-device list on the first request.
    "VLLM_USE_RAY_V2_EXECUTOR_BACKEND=0"
    "VLLM_USE_RAY_COMPILED_DAG=1"
    "VLLM_USE_RAY_COMPILED_DAG_OVERLAP_COMM=0"
    "RAY_EXPERIMENTAL_NOSET_HIP_VISIBLE_DEVICES=0"
    "NCCL_SOCKET_IFNAME=${vllmFabricInterface}"
    "GLOO_SOCKET_IFNAME=${vllmFabricInterface}"
    "NCCL_IB_HCA=${vllmFabricHca}"
    "NCCL_IB_DISABLE=0"
    "NCCL_IB_GID_INDEX=3"
    # DSCP 26 maps to the CRS804's lossless RoCE traffic class.
    "NCCL_IB_TC=104"
    # This iGPU/CX5 path has neither peermem nor working DMA-BUF memory
    # registration. Keep NET/IB enabled, but stage collectives via host RAM.
    "NCCL_DMABUF_ENABLE=0"
    "NCCL_NET_GDR_LEVEL=0"
    "NCCL_DEBUG=INFO"
    "NCCL_DEBUG_SUBSYS=INIT,NET"
  ];
  assertCx5SharedEthernetProfile = pkgs.writeShellScript "assert-cx5-shared-ethernet-profile" ''
    set -euo pipefail

    fw_version="$(${pkgs.coreutils}/bin/cat /sys/class/infiniband/mlx5_0/fw_ver)"
    if [[ "$fw_version" != 16.35.3502 ]]; then
      echo "CX5 SharedIO drift: firmware is '$fw_version', expected '16.35.3502'" >&2
      exit 1
    fi

    query="$(${pkgs.mstflint}/bin/mstconfig -e -d c3:00.0 q)"

    current_value() {
      local key="$1"
      printf '%s\n' "$query" | ${pkgs.gawk}/bin/awk -v key="$key" '
        {
          start = ($1 == "*") ? 2 : 1
          if ($start == key) {
            print $(start + 2)
            exit
          }
        }
      '
    }

    failed=0
    check() {
      local key="$1" expected="$2" actual
      actual="$(current_value "$key")"
      if [[ "$actual" != "$expected" ]]; then
        echo "CX5 SharedIO drift: $key is '$actual', expected '$expected'" >&2
        failed=1
      fi
    }

    check PORT_OWNER ${lib.escapeShellArg expectedCx5PortOwner}
    check NUM_OF_PF 2
    check NUM_OF_VFS 8
    check SRIOV_EN 'True(1)'
    check MULTI_PORT_VHCA_EN 'False(0)'
    check LINK_TYPE_P1 'ETH(2)'
    check LINK_TYPE_P2 'ETH(2)'
    check ROCE_CONTROL ${lib.escapeShellArg expectedCx5RoceControl}
    exit "$failed"
  '';
  linuxPackagesThunderbolt =
    (pkgs.linuxPackagesFor tbvPackages.linux-thunderbolt).extend (_: super: {
      ryzen-smu = super.ryzen-smu.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ lib.optionals
          (lib.versionAtLeast super.kernel.version "7.2")
          [ ../../../profiles/patches/ryzen-smu-linux-7.2-cpuid-header.patch ];
      });
    });
in
{
  /*
    FEVM Strix Halo
  */
  users.groups.video.members = map (n: "nixbld${toString n}") (lib.range 1 32);
  users.groups.render.members = map (n: "nixbld${toString n}") (lib.range 1 32);

  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableDevelopment = true;
    };
    # netconsole.sender = {
    #   enable = builtins.elem index [ 1 2 ];
    #   name = "tbv-${hostName}";
    #   device = "eno1";
    #   localIp = network.primaryIp self;
    #   targetIp = network.primaryIp network.hosts.trex;
    #   targetPort = 6666;
    #   # Strix resolves trex's OVS host interface to this MAC at runtime.
    #   targetMac = "ae:6b:39:5c:92:6a";
    #   extended = true;
    # };
    # ramoops = lib.mkIf (builtins.elem index [ 1 2 ]) {
    #   enable = true;
    #   memAddress = "0x205d000000";
    # };
    xmrig = {
      enable = false;
      package = pkgs.xmrig-zen5;
    };
  };

  system.stateVersion = "24.11";

  hardware.cpu.amd.ryzen-smu.enable = true;
  programs.ryzen-monitor-ng.enable = true;

  environment.systemPackages = [
    pkgs.kexec-tools
  ]
  ++ lib.optional (tbvHipGdaProbes != null) tbvHipGdaProbes
  ++ lib.optionals enableSharedCx5 [
    pkgs.mlnx-mft
  ]
  ++ lib.optionals enableCx5Fabric [
    pkgs.perftest
    pkgs.iperf3
  ]
  ++ lib.optionals enableSharedCx5 [
    vllmStrix
  ]
  ++ lib.optional enableSharedIb pkgs.mlnx-opensm;
  environment.etc."mft/mft.conf" = lib.mkIf enableSharedCx5 {
    source = "${pkgs.mlnx-mft}/etc/mft/mft.conf";
  };

  # boot.binfmt.emulatedSystems = ["aarch64-linux"];
  boot.loader.systemd-boot.configurationLimit = lib.mkForce 4;
  boot.kernelPackages = lib.mkOverride 900 linuxPackagesThunderbolt;

  boot.kernelParams =
    [
    ]
    # Netboot hosts skip profiles/uefi-boot.nix, which normally supplies
    # these host-class tuning params.
    ++ lib.optionals netboot [
      "msr.allow_writes=on"
      "mitigations=off"
    ]
    # Disabled after strix-1 amdgpu failed to fetch VBIOS from ACPI VFCT while
    # booted with these experimental PCIe enumeration parameters.
    ++ lib.optionals false [
      "pci=realloc,assign-busses"
      "pcie_ports=native"
    ];

  deployment.targetHost = network.primaryIp self;
  deployment.targetUser = "grw";

  sops.secrets.mosquitto-password = mkSecret "mosquitto-password" {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  hardware.strixHalo = {
    enable = true;
    amdgpuDpmState = "performance";
    amdgpuPerformanceLevel = "high";
  };

  # Strix 1/2 share one dual-port ConnectX-5 SharedIO adapter and Strix 3/4
  # share the other. All four physical ports connect to the CRS804 Ethernet
  # fabric; hardware.infiniband supplies the verbs/RDMA userspace.
  hardware.infiniband = {
    enable = enableCx5Fabric;
    guids = lib.optionals (enableSharedIb && index == 4) [ "0x1c34da03006112b0" ];
  };

  # Strix Halo GPU workloads use UMA heavily. Large vLLM runs can leave
  # little "available" RAM while still being healthy, so earlyoom kills the
  # benchmark runner or EngineCore before the kernel OOM killer would act.
  services.earlyoom.enable = lib.mkForce false;

  boot.initrd.availableKernelModules = lib.mkIf (index == 2 && !netboot) (lib.mkForce [
    "nvme"
    "md_mod"
    "raid0"
    "ext4"
    "xhci_hcd"
    "xhci_pci"
    "hid_generic"
    "usbhid"
    "atkbd"
    "i8042"
  ]);

  disko.devices = lib.mkIf (!netboot) (
    if singleDisk
    then {
      disk.disk1 = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    }
    else {
      disk = {
        disk1 = {
          type = "disk";
          device = "/dev/nvme0n1";
          content = {
            type = "gpt";
            partitions = {
              "boot-1" = {
                size = "512M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "umask=0077" ];
                };
              };
              mdadm = {
                size = "100%";
                content = {
                  type = "mdraid";
                  name = "raid0";
                };
              };
            };
          };
        };
        disk2 = {
          type = "disk";
          device = "/dev/nvme1n1";
          content = {
            type = "gpt";
            partitions = {
              "boot-2" = {
                size = "512M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot-fallback";
                  mountOptions = [ "umask=0077" ];
                };
              };
              mdadm = {
                size = "100%";
                content = {
                  type = "mdraid";
                  name = "raid0";
                };
              };
            };
          };
        };
      };
      mdadm.raid0 = {
        type = "mdadm";
        level = 0;
        content = {
          type = "gpt";
          partitions.primary = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    }
  );

  imports = (with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd
    common-gpu-amd
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/headless.nix
    ../../../profiles/radeon.nix

    ../../../services/buildfarm-executor.nix
    ../../../profiles/nas-mounts.nix
    ../../../services/buildfarm-slave.nix
    ../../../services/hydra-builder-slave.nix

    ../../../profiles/thunderbolt-bridge.nix

    inputs.disko.nixosModules.disko
    inputs.nix-strix-halo.nixosModules.default
    inputs.nix-strix-halo.nixosModules.benchmark-runner
    inputs.nix-strix-halo.nixosModules.rpc-server
    inputs.nix-strix-halo.nixosModules.fastflowlm
    inputs.nix-strix-halo.nixosModules.ec-su-axb35
    inputs.nix-strix-halo.nixosModules.ryzenadj
    inputs.nix-strix-halo.nixosModules.amduprof

    ../../../profiles/amd-npu.nix
  ]) ++ [
    (if netboot
     then ../../../profiles/netboot-client.nix
     else ../../../profiles/uefi-boot.nix)
  ] ++ lib.optionals enableUsb4Rdma [
    ../../../profiles/thunderbolt-ibverbs-kernel.nix
  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = lib.mkForce false;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
    ];
  };

  services.ec-su-axb35 =
    {
      enable = true;
      monitor.enable = true;
      powerMode = "performance";
    };

  # Writing the EC power mode restores the board's stock SMU limits. Apply
  # RyzenAdj afterwards so the configured package limits win deterministically.
  systemd.services.ryzenadj.after = [ "ec-su-axb35-config.service" ];

  services.ryzenadj = {
    enable = true;
    stapmLimit = ryzenAdjLimits.stapm;
    fastLimit = ryzenAdjLimits.fast;
    slowLimit = ryzenAdjLimits.slow;
    # UINT32_MAX is RyzenAdj's "not supplied" sentinel, so this is the
    # largest time constant its CLI can actually send to the SMU.
    stapmTime = 4294967294;
    apuSlowLimit = ryzenAdjLimits.apuSlow;
    maxPerformance = true;
    # Strix Halo clips tctl above 98 C. Setting this also raises the visible
    # STT APU/dGPU limits; direct apuSkinTemp/dgpuSkinTemp writes are not
    # supported by ryzenadj on this family.
    tctlTemp = 98;
    # Keep Curve Optimizer neutral while validating long-running inference.
    # Aggressive all-core undervolts can fail only under sustained decode load.
    curveOptimizer = {
      enable = true;
      offset = 0;
      graceSeconds = 0;
    };
  };

  programs.amduprof = {
    enable = true;
    powerProfiling.enable = true;
  };

  nix.settings = {
    system-features = [
      "gccarch-znver5"
      "rocm"
      "gfx1151"
      "aimax395"
      "kvm"
      "nixos-test"
      "big-parallel"
    ];

    # FastFlowLM bench derivations talk to the NPU via XRT, which opens
    # /dev/accel/accel0 (amdxdna DRM accel device) and walks sysfs to
    # enumerate devices (xrt::device(0) needs PCI topology to find the
    # NPU, which lives under /sys/devices and /sys/bus/pci). ROCm's libdrm
    # path also needs /sys/dev/char to classify render nodes correctly.
    # Models are pre-staged at /models/flm/ by `flm pull` with
    # FLM_MODEL_PATH set.
    extra-sandbox-paths = [
      "/dev/dri"
      "/dev/kfd"
      "/dev/shm"
      "/dev/accel"
      "/sys/class/drm"
      "/sys/class/kfd"
      "/models"
      "/sys/class/accel"
      "/sys/bus/pci"
      "/sys/devices"
      "/sys/dev"
      "/proc"
    ];
  };

  benchmark.runners.strix-halo = {
    requireIommuOff = false;
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
    systemFeatures = [
      "gccarch-znver5"
      "rocm"
      "aimax395"
      "kvm"
      "nixos-test"
      "big-parallel"
    ];
  };

  # FastFlowLM pins NPU input/output buffers with mlock; on the default
  # 8 MB nixbld limit it warns and falls back to pageable memory, which
  # bench numbers depend on avoiding. nix-daemon spawns builders so the
  # limit must be set on the daemon's systemd unit.
  systemd.services.nix-daemon.serviceConfig.LimitMEMLOCK = "infinity";

  # ROCm build-time JIT derivations run in Nix's sandbox without the
  # caller's supplemental groups. Some ROCm imports still touch the primary
  # DRM node before settling on the render node, so expose it like the NPU
  # accel device below.
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ATTRS{vendor}=="0x1002", MODE="0666"
  '';

  # NPU server. The fastflowlm module installs a MODE=0666 udev
  # rule on /dev/accel/accel0 so the service and the bench-flm-*
  # nixbld builders both have access without per-user group plumbing.
  services.fastflowlm = {
    enable = false;
    model = "gpt-oss:20b";
    openFirewall = false;
  };

  services = {
    fstrim.enable = true;
    fwupd.enable = true;
    iperf3 = {
      enable = true;
      openFirewall = true;
    };
  };

  # On netboot hosts /models is an NFS automount from trex and the server
  # side owns directory creation (chown from an all_squash client fails).
  systemd.tmpfiles.rules = lib.optionals (!netboot) [
    "d /models 0755 root root -"
    "d /models/.cache 0775 grw users -"
    "d /models/.cache/huggingface 0775 grw users -"
  ];

  # Point all HuggingFace tooling at the read-only /models snapshot and keep
  # compute nodes strictly offline w.r.t. the Hub — model acquisition belongs
  # to trex (which serves /strix-models). This makes the per-service
  # vllmServiceEnvironment offline flags the global default too, so interactive
  # ssh sessions and the hellas-ai-video runners don't need to set HF_HOME.
  environment.variables = {
    HF_HOME = "/models/.cache/huggingface";
    HF_HUB_OFFLINE = "1";
    TRANSFORMERS_OFFLINE = "1";
    HF_HUB_DISABLE_TELEMETRY = "1";
    VLLM_USE_RAY_V2_EXECUTOR_BACKEND = "0";
    VLLM_USE_RAY_COMPILED_DAG = "1";
    VLLM_USE_RAY_COMPILED_DAG_OVERLAP_COMM = "0";
    RAY_EXPERIMENTAL_NOSET_HIP_VISIBLE_DEVICES = "0";
  };

  profiles.thunderbolt-bridge = {
    bridgeThunderboltNet = false;
    enableThunderboltNet = enableUsb4Tcp;
  };

  hardware."thunderbolt-ibverbs" = lib.mkMerge [
    {
      enable = lib.mkForce enableUsb4Rdma;
      blacklist.enable = lib.mkForce enableUsb4Rdma;
    }
    (lib.mkIf enableUsb4Rdma {
      loadOnBoot = true;

      config = {
        profile = "linux_perf";
        compat = "off";
        tbnet = "prefer_rdma";
        tbnet_identity = "off";
        # Use the normal LAN address for verbs GIDs and control-plane routing;
        # USB4 payload traffic still uses the native tbverbs DMA rings.
        roce_netdev = "eno1";
        lanes = "auto";
        bind_services = true;
        allocate_rings = true;
        start_rings = true;
        negotiate_native = true;
        enable_tunnels = true;
        native_data = true;
        native_fragment_striping = true;
        native_p2p_zcopy = false;
        native_p2p_host_stream = false;
        zcopy_min_bytes = 4294967295;
        native_rx_p2p_probe = false;
        native_rx_p2p_single_rx = false;
        native_rx_p2p_shared_ring_unsafe = false;
        native_rx_one_deep = false;
        native_rx_p2p_lane = 1;
        apple_data = false;
        register_verbs = true;
      };

      check = {
        enable = true;
        afterReload = true;
        requireVerbs = true;
        expectedNativeControl = "source_aware";
        # Current Strix topology exposes two ready rails per node; requiring
        # four makes otherwise successful Colmena activations fail.
        minReadyRails = 2;
        # The strix-3/4 USB4 peer currently negotiates 10 Gb/s per native rail;
        # strix-1/2 retain their 20 Gb/s expectation.
        expectedRailSpeed = if enableSharedCx5 then "10Gb/s" else "20Gb/s";
        timeoutSeconds = 75;
      };
    })
  ];

  networking = {
    inherit hostName;
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    useDHCP = lib.mkForce false;
    firewall = {
      enable = false;
    };
  };

  boot.extraModprobeConfig = ''
    options thunderbolt xdomain=1
    options thunderbolt_net e2e=0 tx_e2e=0
    options cfg80211 ieee80211_regdom=CH
    options sp5100_tco heartbeat=30 nowayout=1 action=0
  '';

  boot.kernelModules = [ "sp5100_tco" ] ++ lib.optionals enableCx5Fabric [
    "ib_umad"
  ] ++ lib.optionals enableSharedIb [ "ib_ipoib" ];

  boot.kernel.sysctl = {
    # Latency-biased network tuning for distributed inference control paths.
    # busy_{read,poll} trade CPU for lower queue wakeup latency.
    "net.core.busy_read" = 100;
    "net.core.busy_poll" = 100;
    "net.ipv4.tcp_low_latency" = 1;
    "net.ipv4.tcp_fastopen" = 3;
    # Allow intermediate nodes to forward TP control-plane packets between
    # strix machines that are not directly Thunderbolt-connected.
    "net.ipv4.ip_forward" = 1;
    # Increase socket buffers so Thunderbolt bandwidth (≥40 Gb/s) is not
    # bottlenecked by the default 4 MiB kernel cap.
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.ipv4.tcp_rmem" = "4096 87380 134217728";
    "net.ipv4.tcp_wmem" = "4096 65536 134217728";
  };



  users.users.grw.extraGroups = [ "networkmanager" ];

  systemd.network =
    let
      hasDirectThunderbolt = enableUsb4Tcp;
      useArdma0 =
        enableUsb4Rdma
        && config.hardware."thunderbolt-ibverbs".config.tbnet_identity == "minimal_packet";
      thunderboltIp = "10.0.${toString (index + 3)}.2/24";
    in
    {
      enable = true;
      wait-online = {
        enable = true;
        anyInterface = true;
      };
      netdevs =
        lib.optionalAttrs useArdma0
          {
            "30-ardma0" = {
              netdevConfig = {
                Kind = "dummy";
                Name = "ardma0";
              };
            };
          }
        // lib.optionalAttrs enableUsb4Tcp {
          # Layer-2 bridge for strix-to-strix Thunderbolt TCP (TP control plane).
          # STP prevents loops in ring/mesh topologies.
          "25-br-strix" = {
            netdevConfig = {
              Kind = "bridge";
              Name = "br.strix";
            };
            bridgeConfig.STP = true;
          };
        };
      networks = {
        "10-lan" = {
          matchConfig.Name = "eno1";
          address = [ (network.cidrOf "lan" self.addresses.lan) ];
          gateway = [ network.routerIp ];
          dns = [ network.routerIp ];
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = true;
          } // lib.optionalAttrs netboot {
            # The NFS root was configured by the initrd on this interface;
            # never let networkd flush it while taking over.
            KeepConfiguration = "static";
          };
          linkConfig = {
            RequiredForOnline = "routable";
            # The diskless root remains live over this LAN link after stage 2.
            # Keep it at Ethernet's standard MTU: the cluster's smart-switch
            # path does not reliably pass jumbo frames, and changing eno1 to
            # 9000 here strands NFS while small ICMP packets still work.
            MTUBytes = if netboot then "1500" else "9000";
          };
        };
        "10-aquantia" = {
          matchConfig.Driver = "atlantic";
          networkConfig = {
            DHCP = "no";
            LinkLocalAddressing = "no";
            ConfigureWithoutCarrier = true;
          };
          linkConfig.RequiredForOnline = "no";
        };
      } // lib.optionalAttrs enableSharedIb {
        # Use opposite physical ports on the looped dual-port HCA.  This gives
        # application traffic an ordinary IPoIB address while verbs benchmarks
        # can select mlx5_1 on strix-3 and mlx5_0 on strix-4 directly.
        "15-shared-ib" = {
          matchConfig.Name = if index == 3 then "ibp195s0f1" else "ibp195s0f0";
          address = [ "10.5.0.${toString index}/24" ];
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = false;
            LinkLocalAddressing = "no";
          };
          linkConfig = {
            MTUBytes = "4092";
            RequiredForOnline = "no";
          };
        };
      } // lib.optionalAttrs enableSharedCx5 {
        # Raise both Ethernet PFs of the shared ConnectX-5, but put the fabric
        # address on exactly one PF per host.  Addressing both physical ports
        # in the same CRS804 VLAN would create ambiguous routes.
        "15-shared-cx5-fabric" = {
          matchConfig.Name = vllmFabricInterface;
          address = [ (network.cidrOf "fabric" self.addresses.fabric) ];
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = false;
            LinkLocalAddressing = "no";
            ConfigureWithoutCarrier = true;
          };
          linkConfig = {
            MTUBytes = "9000";
            RequiredForOnline = "no";
          };
        };
        "16-shared-cx5-unaddressed" = {
          matchConfig.Name = if useCx5Port1 then "enp195s0f0np0" else "enp195s0f1np1";
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = false;
            LinkLocalAddressing = "no";
            ConfigureWithoutCarrier = true;
          };
          linkConfig = {
            MTUBytes = "9000";
            RequiredForOnline = "no";
          };
        };
      } // lib.optionalAttrs (index == 1) {
        # Some firmware profiles expose a duplicate SharedIO PCIe view on
        # strix-1. Keep it up but unaddressed; enp195s0f1np1 owns .101.
        "17-strix1-cx5-port1-duplicate" = {
          matchConfig.Name = "enp196s0f1np1";
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = false;
            LinkLocalAddressing = "no";
            ConfigureWithoutCarrier = true;
          };
          linkConfig = {
            MTUBytes = "9000";
            RequiredForOnline = "no";
          };
        };
      } // lib.optionalAttrs (hasDirectThunderbolt && reserveThunderbolt0ForMac) {
        # Direct point-to-point link to Mac. Wins over the profile's
        # 50-thunderbolt bridge match by lexical order on the iface name.
        "20-thunderbolt0" = {
          matchConfig.Name = "thunderbolt0";
          address = [ thunderboltIp ];
          networkConfig = {
            LinkLocalAddressing = "no";
            IPv6AcceptRA = false;
            ConfigureWithoutCarrier = true;
          };
          linkConfig = {
            MTUBytes = "9000";
            RequiredForOnline = "no";
          };
        };
      } // lib.optionalAttrs useArdma0 {
        "30-ardma0" = {
          matchConfig.Name = "ardma0";
          address = [ (lib.replaceStrings [ "/24" ] [ "/32" ] thunderboltIp) ];
          routes = lib.optionals (index == 2) [
            { Destination = "10.0.5.3/32"; }
          ];
          networkConfig = {
            LinkLocalAddressing = "no";
            IPv6AcceptRA = false;
            ConfigureWithoutCarrier = true;
          };
          linkConfig.RequiredForOnline = "no";
        };
      } // lib.optionalAttrs enableUsb4Tcp {
        # Enslave strix-to-strix thunderbolt-net interfaces into br.strix.
        # Optionally excludes thunderbolt0 when reserved for the Mac p2p link.
        # Wins over the profile's 50-thunderbolt match by sort order.
        "25-thunderbolt-strix" = {
          matchConfig = {
            Driver = "thunderbolt-net";
          } // lib.optionalAttrs reserveThunderbolt0ForMac {
            Name = "!thunderbolt0";
          };
          networkConfig.Bridge = "br.strix";
          linkConfig = {
            MTUBytes = "9000";
            RequiredForOnline = "no";
          };
        };
        # Static IP on the strix bridge: 10.4.0.{index}/24.
        # strix-1=10.4.0.1, strix-2=10.4.0.2, strix-3=10.4.0.3, strix-4=10.4.0.4
        "26-br-strix" = {
          matchConfig.Name = "br.strix";
          address = [ "10.4.0.${toString index}/24" ];
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = false;
            LinkLocalAddressing = "no";
            ConfigureWithoutCarrier = true;
          };
          linkConfig = {
            MTUBytes = "9000";
            RequiredForOnline = "no";
          };
        };
      };
    };
}
