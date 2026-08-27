{ pkgs
, lib
, inputs
, config
, mkSecret
, network
, ...
}:
let
  self = network.hosts.fuckup;
  moshi = pkgs.moshi.override {
    cudaPackages = pkgs.cudaPackages_12_8;
    cudaCapability = "8.9";
  };
  moshiConfig = pkgs.writeText "moshi-bf16.json" (builtins.toJSON {
    instance_name = "fuckup-bf16";
    hf_repo = "kyutai/moshiko-candle-bf16";
    lm_model_file = "/models/.cache/huggingface/moshi/moshiko-candle-bf16/model.safetensors";
    text_tokenizer_file = "/models/.cache/huggingface/moshi/moshiko-candle-bf16/tokenizer_spm_32k_3.model";
    log_dir = "$HOME/.local/state/moshi/logs";
    mimi_model_file = "/models/.cache/huggingface/moshi/moshiko-candle-bf16/tokenizer-e351c8d8-checkpoint125.safetensors";
    mimi_num_codebooks = 8;
    static_dir = "/models/.cache/huggingface/moshi/web-dist";
    addr = "127.0.0.1";
    port = 8998;
    cert_dir = "$HOME/.local/state/moshi/certs";
  });
  moshiBf16 = pkgs.writeShellScriptBin "moshi-bf16" ''
    set -euo pipefail

    state_dir="$HOME/.local/state/moshi"
    mkdir -p "$state_dir/logs" "$state_dir/certs"
    cd "$state_dir"
    exec ${moshi}/bin/moshi-backend --config ${moshiConfig} standalone "$@"
  '';
in
{
  /*
    AMD Ryzen 9 9950X3D
  */
  sconfig = {
    profile = "desktop";
    home-manager = {
      enable = true;
      enableDevelopment = true;
      enableGraphical = true;
      enableCad = true;
    };
    xmrig = with pkgs; {
      enable = true;
      package = xmrig-zen5;
      cudaPlugin = null;
      httpApi.enable = true;
      httpApi.accessToken = "xmrig";
      inhibit.dota2.enable = true;
    };
  };

  system.stateVersion = "25.05";

  deployment.targetHost = network.primaryIp self;
  deployment.targetUser = "grw";

  sops.secrets.mosquitto-password = mkSecret "mosquitto-password" {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets.hf-token = mkSecret "hf-token" { };
  sops.templates."hellas-env".content = ''
    HF_TOKEN=${config.sops.placeholder."hf-token"}
  '';

  systemd.services.hellas.serviceConfig.EnvironmentFile =
    config.sops.templates."hellas-env".path;

  boot.tmp.useTmpfs = lib.mkForce false;

  hardware.enableAllHardware = true;
  nix.settings.system-features = [ "gccarch-znver5" "rtx4090" "9950x3d" ];

  programs.gpu-screen-recorder.enable = true;

  # Shared read-only model cache served by trex instead of a local HF cache.
  # Strix nodes do not use this NFS path; they mount the pinned NVMe/RDMA
  # snapshot directly.
  fileSystems."/models" = {
    device = "${network.primaryIp network.hosts.trex}:/strix-models";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "ro"
      "nofail"
      "_netdev"
      "x-systemd.automount"
      "rsize=1048576"
      "wsize=1048576"
      "nconnect=8"
    ];
  };
  boot.supportedFilesystems = [ "nfs" ];

  # Point HuggingFace tooling at the shared snapshot and stay offline w.r.t.
  # the Hub — model acquisition belongs to trex (mirrors the strix nodes).
  environment.variables = {
    HF_HOME = "/models/.cache/huggingface";
    HF_HUB_OFFLINE = "1";
    TRANSFORMERS_OFFLINE = "1";
    HF_HUB_DISABLE_TELEMETRY = "1";
  };

  environment.systemPackages = [
    pkgs.kexec-tools
    moshi
    moshiBf16
    pkgs.gpu-screen-recorder-gtk
    pkgs.wl-screenrec
    (pkgs.writeShellScriptBin "wl-capture" ''
      set -euo pipefail

      output="''${WL_CAPTURE_OUTPUT:-DP-3}"
      fps="''${WL_CAPTURE_FPS:-60}"
      codec="''${WL_CAPTURE_CODEC:-h264}"
      dir="''${WL_CAPTURE_DIR:-$HOME/Videos/Screencasts}"
      mkdir -p "$dir"

      file="$dir/wl-capture-$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S).mp4"
      export PATH="/run/wrappers/bin:$PATH"
      exec ${pkgs.gpu-screen-recorder}/bin/gpu-screen-recorder \
        -w "$output" \
        -f "$fps" \
        -k "$codec" \
        -encoder gpu \
        -q high \
        -cursor yes \
        -o "$file"
    '')
  ];

  services.hellas = {
    enable = true;
    # package = inputs.hellas.packages.x86_64-linux.server-cuda;
    openFirewall = true;
    port = 31145;
    executePolicy = [
      "hf/lewtun/talkie-1930-13b-it-hf"
      "hf/Qwen/Qwen3.5-0.8B"
    ];
    metricsPort = 9400;
    # Placeholder assurance terms (mirrors nix/tests/e2e.nix) until the
    # attested-execution plan drops these flags.
    assuranceCodec = "tpm2.quote.v1";
    assurancePolicy = "0000000000000000000000000000000000000000000000000000000000000000";
    graffiti = "cuda12-sm89";
    preloadWeights = [
      "Qwen/Qwen3.5-0.8B"
    ];
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

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd
    common-gpu-amd
    inputs.disko.nixosModules.disko

    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/nas-mounts.nix
    # ../../../profiles/radeon.nix
    ../../../profiles/nvidia.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/zfs.nix
    ../../../profiles/development.nix
    ../../../profiles/graphical.nix
    ../../../profiles/displaylink.nix
    ../../../profiles/wayland-compositors-test.nix

    ../../../profiles/thunderbolt-ibverbs-kernel-stable.nix
    ../../../profiles/thunderbolt-bridge.nix

    ../../../services/buildfarm-slave.nix
    ../../../services/hydra-builder-slave.nix

    inputs.nix-strix-halo.nixosModules.default
    inputs.nix-strix-halo.nixosModules.benchmark-runner
    inputs.hellas.nixosModules.default
    # inputs.nix-strix-halo.nixosModules.tuning

    ./fabric-rdma-vf.nix
    ./nvme-models.nix
    ./claw-usb-live.nix
  ];

  benchmark.runners.cuda-rtx4090 = {
    requireIommuOff = false;
    gpus = [
      {
        type = "nvidia";
        arch = "rtx4090";
      }
    ];
    systemFeatures = [
      "benchmark"
      "cuda"
      "nvidia"
    ];
    extraSandboxPaths = [
      "/proc/driver/nvidia"
      "/run/opengl-driver"
      "/run/opengl-driver-lib=/run/opengl-driver/lib"
      "${config.hardware.nvidia.package}"
    ];
  };

  home-manager.users.grw =
    { lib
    , pkgs
    , ...
    }: {
      home.activation.kwinGameInput = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
          --file "$HOME/.config/kwinrc" \
          --group MouseBindings \
          --key CommandAllKey Meta
      '';
    };

  networking.firewall.allowedTCPPorts = [ 8080 8081 ];

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = lib.mkForce true;
    };
  };

  # ZFS snapshot management - long retention for backup archive
  services.sanoid = {
    enable = true;
    interval = "hourly";
    datasets."archive/pool3d" = {
      recursive = true;
      autosnap = false; # Don't create snapshots, just prune received ones
      hourly = 48;
      daily = 90;
      weekly = 52;
      monthly = 24;
    };
  };

  # Allow trex syncoid user to SSH in for replication
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB5dlmnSV46Mvtz5f+yVh23RnUPUw/T6Kcmx0LkODx5C syncoid@trex"
  ];

  # Import the archive pool at boot
  boot.zfs.extraPools = [ "archive" ];

  disko.devices = {
    disk = {
      nvme = {
        device = "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "500M";
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
    };
  };

  hardware.mediatek-mt7927.enable = true;

  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom="CH"
    options sp5100_tco heartbeat=30 nowayout=1 action=0
  '';

  boot.kernelModules = [ "sp5100_tco" ];




  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = lib.mkForce true;
  };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "performance";
  };

  profiles.thunderbolt-bridge = {
    enableThunderboltNet = false;
    bridgeThunderboltNet = false;
  };

  hardware.thunderbolt-ibverbs = {
    enable = true;
    loadOnBoot = false;
    blacklist.enable = true;
    config = {
      profile = "linux_perf";
      compat = "off";
      tbnet = "prefer_rdma";
      tbnet_identity = "off";
      lanes = "2";
      bind_services = true;
      allocate_rings = true;
      start_rings = true;
      negotiate_native = true;
      enable_tunnels = true;
      native_control_trace = true;
      native_ready_timeout_optimistic = true;
      register_verbs = true;
      roce_netdev = "br0.lan";
    };
  };

  networking = {
    hostName = "fuckup";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    useDHCP = false;
    firewall.enable = false;
    # Let NetworkManager own only WiFi; systemd-networkd keeps the
    # wired bridge it already configures below.
    networkmanager = {
      enable = true;
      settings.keyfile.unmanaged-devices = "*,except:type:wifi";
    };
  };

  systemd.network =
    let
      lanBridge = "br0.lan";
    in
    {
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
          bridgeConfig.STP = true;
        };
      };
      networks = {
        "10-bridge" = {
          matchConfig.Name = lanBridge;
          networkConfig.IPv6AcceptRA = true;
          address = [ (network.cidrOf "lan" self.addresses.lan) ];
          gateway = [ network.routerIp ];
          dns = [ network.routerIp ];
        };
        "10-mlx5" = {
          matchConfig.Driver = "mlx5_core";
          networkConfig = {
            Bridge = lanBridge;
            ConfigureWithoutCarrier = true;
          };
          # Jumbo on the ConnectX PFs so the RoCE VF in fabric-rdma-vf.nix can
          # reach MTU 9000 -- a VF's MTU is capped by its PF's. This does not
          # give br0.lan jumbo: a Linux bridge takes the minimum MTU of its
          # ports and the igc/aquantia members stay at 1500, so LAN behaviour
          # is unchanged (verified: br0.lan remained 1500 with both PFs at
          # 9000, and the router stayed reachable at 0.078 ms).
          linkConfig.MTUBytes = "9000";
          linkConfig.RequiredForOnline = "enslaved";
        };
        "10-igc" = {
          matchConfig.Driver = "igc";
          networkConfig = {
            Bridge = lanBridge;
            ConfigureWithoutCarrier = true;
          };
          linkConfig.RequiredForOnline = "enslaved";
        };
        # enp10s0 has the long cable to the 400G switch management port,
        # which lands in the cluster MANAGEMENT LAN (23.x), not the fabric
        # (25.x). It must stay out of br0.lan (bridging it loops the LAN via
        # the mgmt switch) and carries no address: fuckup has no dataplane
        # attachment to the 192.168.25.0/24 fabric without an SFP+ RJ45
        # transceiver or DAC between the CX5 and the 400G switch.
        "10-fabric" = {
          matchConfig.Name = "enp10s0";
          networkConfig.ConfigureWithoutCarrier = true;
          linkConfig.RequiredForOnline = false;
          linkConfig.ActivationPolicy = "down";
        };
        # Keep the second Aquantia port on the LAN bridge as before.
        "11-aquantia-lan" = {
          matchConfig.Name = "enp11s0";
          networkConfig = {
            Bridge = lanBridge;
            ConfigureWithoutCarrier = true;
          };
          linkConfig.RequiredForOnline = false;
        };
      };
    };
}
