index: {
  pkgs,
  lib,
  inputs,
  mkSecret,
  config,
  network,
  ...
}: let
  hostName = "strix-${toString index}";
  self = network.hosts.${hostName};
in {
  /*
  FEVM Strix Halo
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableDevelopment = true;
    };
    xmrig = {
      enable = false;
      package = pkgs.xmrig-zen5;
    };
  };

  system.stateVersion = "24.11";

  hardware.cpu.amd.ryzen-smu.enable = true;
  programs.ryzen-monitor-ng.enable = true;

  boot.binfmt.emulatedSystems = ["aarch64-linux"];
  boot.loader.systemd-boot.configurationLimit = lib.mkForce 4;
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

    ../../../profiles/thunderbolt-bridge.nix
    ../../../profiles/usb4-rdma-kernel.nix

    inputs.nix-strix-halo.nixosModules.default
    inputs.nix-strix-halo.nixosModules.rocm-narrow
    inputs.nix-strix-halo.nixosModules.tuning
    inputs.nix-strix-halo.nixosModules.benchmark-runner
    inputs.nix-strix-halo.nixosModules.rpc-server
    inputs.nix-strix-halo.nixosModules.disko-raid0
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

  services.ec-su-axb35 = let
    level = 2;
  in {
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
    after = ["ec-su-axb35-config.service"];
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
    after = ["sops-install-secrets.service"];
    wants = ["sops-install-secrets.service"];
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
      # XDNA2 NPU; used by nix-strix-halo's bench-flm-* derivations.
      "npu-strix"
    ];

    # FastFlowLM bench derivations talk to the NPU via XRT, which opens
    # /dev/accel/accel0 (amdxdna DRM accel device), and read pre-staged
    # models from /models/flm/.
    extra-sandbox-paths = [
      "/dev/accel"
      "/sys/class/accel"
      "/models"
    ];
  };

  # Let the nixbld build group open /dev/accel/accel0.
  services.udev.extraRules = ''
    SUBSYSTEM=="accel", KERNEL=="accel*", GROUP="nixbld", MODE="0660"
  '';

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
    enableThunderboltNet = lib.mkIf (builtins.elem index [1 2]) true;
  };

  hardware."thunderbolt-ibverbs" = lib.mkIf (builtins.elem index [1 2]) {
    moduleOptions = {
      profile = "mixed";
      compat = "auto";
      tbnet = "prefer_rdma";
      tbnetIdentity = "minimal_packet";
      tbnetIdentityTbnet = "thunderbolt0";
      tbnetIdentityGid = "ardma0";
      tbnetIdentityMinimalE2e = false;
      roceNetdev = "br0.lan";
      lanes = "2";
      bindServices = true;
      allocateRings = true;
      startRings = true;
      negotiateNative = true;
      enableTunnels = true;
      nativeData = true;
      appleData = true;
      registerVerbs = true;
    };

    check = {
      afterReload = true;
      expectedNativeControl = "source_aware";
      requireVerbs = true;
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
    options sp5100_tco heartbeat=30 nowayout=1
  '';

  boot.kernelModules = ["sp5100_tco"];

  users.users.grw.extraGroups = ["networkmanager"];

  systemd.network = let
    lanBridge = "br0.lan";
    useArdma0 =
      builtins.elem index [1 2]
      && config.hardware."thunderbolt-ibverbs".moduleOptions.tbnetIdentity == "minimal_packet";
    thunderboltIp =
      if index == 1
      then "10.0.4.2/24"
      else "10.0.5.2/24";
  in {
    enable = true;
    wait-online = {
      enable = true;
      anyInterface = true;
    };
    netdevs = {
      "20-${lanBridge}" = {
        netdevConfig = {
          Kind = "bridge";
          Name = lanBridge;
        };
        bridgeConfig = {
          STP = true;
          # 802.1D constraint: forward_delay >= (max_age/2) + 1
          # With max_age=6s, min forward_delay=4s → ~8s convergence instead of 30s
          MaxAgeSec = 6;
          ForwardDelaySec = 4;
        };
      };
    } // lib.optionalAttrs useArdma0 {
      "30-ardma0" = {
        netdevConfig = {
          Kind = "dummy";
          Name = "ardma0";
        };
      };
    };
    networks = {
      "10-bridge" = {
        matchConfig.Name = lanBridge;
        address = [(network.cidrOf "lan" self.addresses.lan)];
        gateway = [network.routerIp];
        dns = [network.routerIp];
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = true;
        };
      };
      "10-lan" = {
        matchConfig.Driver = "r8169";
        networkConfig = {
          Bridge = lanBridge;
          ConfigureWithoutCarrier = true;
        };
        linkConfig.RequiredForOnline = "enslaved";
      };
      "10-aquantia" = {
        matchConfig.Driver = "atlantic";
        networkConfig = {
          Bridge = lanBridge;
          ConfigureWithoutCarrier = true;
        };
        linkConfig.RequiredForOnline = "enslaved";
      };
      # Direct point-to-point link to Mac. Wins over the profile's
      # 50-thunderbolt bridge match by lexical order on the iface name.
      "20-thunderbolt0" = {
        matchConfig.Name = "thunderbolt0";
        address = [thunderboltIp];
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
        address = [(lib.replaceStrings ["/24"] ["/32"] thunderboltIp)];
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
