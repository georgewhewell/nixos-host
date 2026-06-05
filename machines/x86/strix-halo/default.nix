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
  tbvPackages = inputs.thunderbolt-ibverbs-kernel.packages.${pkgs.stdenv.hostPlatform.system} or { };
  tbvHipGdaProbes = tbvPackages."tbv-hip-gda-probes" or null;
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
    netconsole.sender = {
      enable = builtins.elem index [ 1 2 ];
      name = "tbv-${hostName}";
      device = "eno1";
      localIp = network.primaryIp self;
      targetIp = network.primaryIp network.hosts.trex;
      targetPort = 6666;
      # Strix resolves trex's OVS host interface to this MAC at runtime.
      targetMac = "ae:6b:39:5c:92:6a";
      extended = true;
    };
    ramoops = lib.mkIf (builtins.elem index [ 1 2 ]) {
      enable = true;
      memAddress = "0x205d000000";
    };
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
  ] ++ lib.optional (tbvHipGdaProbes != null) tbvHipGdaProbes;

  boot.crashDump = lib.mkIf (builtins.elem index [ 1 2 ]) {
    enable = true;
    reservedMemory = "512M";
    kernelParams = [
      "1"
      "boot.shell_on_fail"
    ];
  };

  # boot.binfmt.emulatedSystems = ["aarch64-linux"];
  boot.loader.systemd-boot.configurationLimit = lib.mkForce 4;

  boot.kernelParams =
    [
      "panic=5"
      "panic_on_oops=1"
      "softlockup_panic=1"
      "hung_task_panic=1"
      "nmi_watchdog=panic,1"
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

  hardware.strixHalo.enable = true;

  # Strix Halo GPU workloads use UMA heavily. Large vLLM runs can leave
  # little "available" RAM while still being healthy, so earlyoom kills the
  # benchmark runner or EngineCore before the kernel OOM killer would act.
  services.earlyoom.enable = lib.mkForce false;

  boot.initrd.availableKernelModules = lib.mkIf (index == 2) (lib.mkForce [
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

  disko.devices = {
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
  };

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd
    common-gpu-amd
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/headless.nix
    ../../../profiles/radeon.nix

    ../../../profiles/uefi-boot.nix
    ../../../services/buildfarm-executor.nix
    ../../../profiles/nas-mounts.nix
    ../../../services/buildfarm-slave.nix
    ../../../services/hydra-builder-slave.nix

    ../../../profiles/thunderbolt-bridge.nix
    ../../../profiles/thunderbolt-ibverbs-kernel.nix

    inputs.disko.nixosModules.disko
    inputs.nix-strix-halo.nixosModules.default
    inputs.nix-strix-halo.nixosModules.benchmark-runner
    inputs.nix-strix-halo.nixosModules.rpc-server
    inputs.nix-strix-halo.nixosModules.fastflowlm
    inputs.nix-strix-halo.nixosModules.ec-su-axb35
    inputs.nix-strix-halo.nixosModules.ryzenadj

    ../../../profiles/amd-npu.nix
  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = lib.mkForce false;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
    ];
  };

  services.ec-su-axb35 =
    let
      level = 2;
    in
    {
      enable = true;
      monitor.enable = true;
      powerMode = "performance";
      fans = {
        fan1 = {
          mode = "fixed";
          inherit level;
        };
        fan2 = {
          mode = "fixed";
          inherit level;
        };
      };
    };

  services.max-perf = {
    enable = true;
    description = "Strix Halo EC fan max-performance";
    after = [ "ec-su-axb35-config.service" ];
    writes = [
      {
        path = "/sys/class/ec_su_axb35/fan1/mode";
        value = "fixed";
      }
      {
        path = "/sys/class/ec_su_axb35/fan1/level";
        value = "5";
      }
      {
        path = "/sys/class/ec_su_axb35/fan2/mode";
        value = "fixed";
      }
      {
        path = "/sys/class/ec_su_axb35/fan2/level";
        value = "5";
      }
    ];
    mqtt = {
      enable = true;
      host = network.routerIp;
      username = "rw";
      passwordFile = config.sops.secrets.mosquitto-password.path;
    };
  };

  systemd.services.max-perf-mqtt = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
  };

  # services.ryzenadj = {
  #   enable = true;
  #   stapmLimit = 132000;ni
  #   fastLimit = 176000;
  #   slowLimit = 154000;
  #   maxPerformance = true;
  #   tctlTemp = 90;
  #   # curveOptimizer = {
  #   #   enable = true;
  #   #   offset = -10;
  #   #   graceSeconds = 60;
  #   # };
  # };

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

  profiles.thunderbolt-bridge = {
    bridgeThunderboltNet = false;
    enableThunderboltNet = lib.mkIf (builtins.elem index [ 1 2 ]) false;
  };

  hardware."thunderbolt-ibverbs" = lib.mkIf (builtins.elem index [ 1 2 ]) {
    blacklist.enable = true;
    loadOnBoot = false;

    config = {
      profile = "linux_perf";
      compat = "off";
      tbnet = "prefer_rdma";
      tbnet_identity = "off";
      roce_netdev = "eno1";
      lanes = "auto";
      bind_services = true;
      allocate_rings = true;
      start_rings = true;
      negotiate_native = true;
      enable_tunnels = true;
      native_data = true;
      native_fragment_striping = true;
      apple_data = false;
      register_verbs = true;
    };

    check = {
      afterReload = true;
      expectedNativeControl = "source_aware";
      requireVerbs = true;
      minReadyRails = 2;
    };
  };

  networking = {
    inherit hostName;
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    useDHCP = lib.mkForce false;
    firewall = {
      enable = false;
    };
    # Temporary: NetworkManager for cloudcutter (Tuya flashing)
    networkmanager = {
      enable = true;
      settings.keyfile.unmanaged-devices = "*,except:interface-name:wlp195s0";
      connectionConfig."connection.autoconnect" = "false";
    };
  };

  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=CH
    options sp5100_tco heartbeat=30 nowayout=1 action=0
  '';

  boot.kernelModules = [ "sp5100_tco" ];

  boot.kernel.sysctl = {
    "kernel.panic" = 5;
    "kernel.watchdog" = 1;
    "kernel.panic_on_oops" = 1;
    "kernel.softlockup_panic" = 1;
    "kernel.hung_task_panic" = 1;
    "kernel.nmi_watchdog" = 1;
    "kernel.hardlockup_panic" = 1;
    "kernel.panic_print" = 63;
  };

  systemd.settings.Manager = {
    RuntimeWatchdogSec = "15s";
    RebootWatchdogSec = "30s";
    KExecWatchdogSec = "30s";
  };

  users.users.grw.extraGroups = [ "networkmanager" ];

  systemd.network =
    let
      useArdma0 =
        builtins.elem index [ 1 2 ]
        && config.hardware."thunderbolt-ibverbs".config.tbnet_identity == "minimal_packet";
      thunderboltIp =
        if index == 1
        then "10.0.4.2/24"
        else "10.0.5.2/24";
    in
    {
      enable = true;
      wait-online = {
        enable = true;
        anyInterface = true;
      };
      netdevs = lib.optionalAttrs useArdma0 {
        "30-ardma0" = {
          netdevConfig = {
            Kind = "dummy";
            Name = "ardma0";
          };
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
          };
          linkConfig.RequiredForOnline = "routable";
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
          networkConfig = {
            LinkLocalAddressing = "no";
            IPv6AcceptRA = false;
            ConfigureWithoutCarrier = true;
          };
          linkConfig.RequiredForOnline = "no";
        };
      };
    };
}
