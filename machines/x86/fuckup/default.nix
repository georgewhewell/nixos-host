{
  pkgs,
  lib,
  inputs,
  config,
  mkSecret,
  network,
  ...
}: let
  self = network.hosts.fuckup;
in {
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
      enable = false;
      package = xmrig-zen5;
      # cudaPlugin = xmrig-cuda-plugin;
      httpApi.enable = true;
      httpApi.accessToken = "xmrig";
      inhibit.dota2.enable = true;
    };
  };

  # GPU-only mining for benchmarking
  # services.xmrig.settings.cpu.enabled = lib.mkForce false;

  system.stateVersion = "25.05";

  deployment.targetHost = network.primaryIp self;
  deployment.targetUser = "grw";

  sops.secrets.mosquitto-password = mkSecret "mosquitto-password" {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets.hf-token = mkSecret "hf-token" {};
  sops.templates."hellas-env".content = ''
    HF_TOKEN=${config.sops.placeholder."hf-token"}
  '';

  systemd.services.hellas.serviceConfig.EnvironmentFile =
    config.sops.templates."hellas-env".path;

  boot.tmp.useTmpfs = lib.mkForce false;

  hardware.enableAllHardware = true;
  nix.settings.system-features = ["gccarch-znver5"];

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
    ../../../profiles/radeon.nix
    ../../../profiles/nvidia.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/zfs.nix
    ../../../profiles/development.nix
    ../../../profiles/graphical.nix
    ../../../profiles/displaylink.nix
    ../../../profiles/wayland-compositors-test.nix
    ../../../profiles/thunderbolt-bridge.nix

    ../../../services/buildfarm-slave.nix

    inputs.nix-strix-halo.nixosModules.default
    inputs.nix-strix-halo.nixosModules.benchmark-runner
    inputs.hellas.nixosModules.default
    # inputs.nix-strix-halo.nixosModules.tuning
  ];

  # llama.cpp built from ggml-org/master with CUDA (sm_89, RTX 4090).
  # Sourced from nix-strix-halo so the master pin + nixpkgs overrides
  # stay in one place; consumed as a flake package because fuckup's
  # pkgsForCuda doesn't itself carry the strix-halo overlay.
  environment.systemPackages = [
    inputs.nix-strix-halo.packages.x86_64-linux.llama-cpp-master-cuda
  ];

  networking.firewall.allowedTCPPorts = [8080 8081];

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
  boot.zfs.extraPools = ["archive"];

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
                mountOptions = ["umask=0077"];
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
  '';

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = lib.mkForce true;
  };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "performance";
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

  systemd.network = let
    lanBridge = "br0.lan";
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
        bridgeConfig.STP = true;
      };
    };
    networks = {
      "10-bridge" = {
        matchConfig.Name = lanBridge;
        networkConfig.IPv6AcceptRA = true;
        address = [(network.cidrOf "lan" self.addresses.lan)];
        gateway = [network.routerIp];
        dns = [network.routerIp];
      };
      "10-mlx5" = {
        matchConfig.Driver = "mlx5_core";
        networkConfig = {
          Bridge = lanBridge;
          ConfigureWithoutCarrier = true;
        };
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
      "10-aquantia" = {
        matchConfig.Driver = "atlantic";
        networkConfig = {
          Bridge = lanBridge;
          ConfigureWithoutCarrier = true;
        };
        linkConfig.RequiredForOnline = "enslaved";
      };
    };
  };
}
