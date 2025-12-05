index: {
  pkgs,
  lib,
  inputs,
  config,
  ...
}: let
  hostName = "strix-${toString index}";
in {
  /*
  FEVM Strix Halo
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
    };
    xmrig = {
      enable = true;
      package = pkgs.xmrig-zen5;
    };
  };

  system.stateVersion = "24.11";

  deployment.targetHost = "${hostName}.lan.satanic.link";
  deployment.targetUser = "grw";

  users.extraUsers.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEtPi2T/lOR9s64SVS4ETOmJgj//nKJxuGD8A+PZxcLb root@trex"
  ];

  nixpkgs.config.permittedInsecurePackages = ["qtwebengine-5.15.19"];

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd
    common-gpu-amd
    ../../../profiles/radeon.nix

    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/development.nix

    ../../../profiles/headless.nix
    ../../../profiles/uefi-boot.nix
    ../../../services/buildfarm-slave.nix

    inputs.nix-llamacpp-rocm.nixosModules.default
    # inputs.nix-llamacpp-rocm.nixosModules.benchmark-runner
    inputs.nix-llamacpp-rocm.nixosModules.disko-raid0
    inputs.nix-llamacpp-rocm.nixosModules.ec-su-axb35
    inputs.nix-llamacpp-rocm.nixosModules.tuning
  ];

  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [
      rocmPackages_6.gfx1151.clr.icd
      # rocm-opencl-runtime
    ];
  };

  # services.benchmark-runner = {
  #   enable = true;
  #   gpuTarget = "gfx1151";
  #   modelsPath = "/models";
  #   ensureModels = [
  #     {
  #       name = "llama-2-7b";
  #       repo = "TheBloke/Llama-2-7B-GGUF";
  #       files = ["llama-2-7b.Q4_K_M.gguf"];
  #     }
  #     {
  #       name = "qwen2.5-32b-instruct";
  #       repo = "Qwen/Qwen2.5-32B-Instruct-GGUF";
  #       files = [
  #         "qwen2.5-32b-instruct-q8_0-00001-of-00009.gguf"
  #         "qwen2.5-32b-instruct-q8_0-00002-of-00009.gguf"
  #         "qwen2.5-32b-instruct-q8_0-00003-of-00009.gguf"
  #         "qwen2.5-32b-instruct-q8_0-00004-of-00009.gguf"
  #         "qwen2.5-32b-instruct-q8_0-00005-of-00009.gguf"
  #         "qwen2.5-32b-instruct-q8_0-00006-of-00009.gguf"
  #         "qwen2.5-32b-instruct-q8_0-00007-of-00009.gguf"
  #         "qwen2.5-32b-instruct-q8_0-00008-of-00009.gguf"
  #         "qwen2.5-32b-instruct-q8_0-00009-of-00009.gguf"
  #       ];
  #     }
  #     {
  #       name = "qwen3-coder-30b-a3b";
  #       repo = "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF";
  #       files = [
  #         "BF16/Qwen3-Coder-30B-A3B-Instruct-BF16-00001-of-00002.gguf"
  #         "BF16/Qwen3-Coder-30B-A3B-Instruct-BF16-00002-of-00002.gguf"
  #       ];
  #     }
  #   ];
  # };

  services.ec-su-axb35 = {
    enable = true;
    monitor.enable = true;
  };

  nix.settings.system-features = ["gccarch-znver5" "kvm" "nixos-test" "big-parallel"];

  # boot.blacklistedKernelModules = ["mlx5_core"];
  environment.systemPackages = with pkgs; [
    # iperf3
    # tbtools
    # pciutils
    # fio
    # lm_sensors

    # geekbench_6
    # passmark-performancetest

    # # llamacpp-rocm.gfx1151-rocwmma

    # (python3.withPackages (ps:
    #   with ps; [
    #     hf-transfer
    #     huggingface-hub
    #   ]))
  ];

  services = {
    fstrim.enable = true;
    fwupd.enable = true;
    hardware.bolt.enable = true;
    iperf3 = {
      enable = true;
      openFirewall = true;
    };
  };

  networking = {
    inherit hostName;
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    useDHCP = true;
    firewall.enable = false;
  };

  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=CH
  '';

  # Thunderbolt network configuration
  boot.kernelModules = ["thunderbolt-net"];
  users.users.grw.extraGroups = ["networkmanager"];

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
      };
    };
    networks = {
      "10-bridge" = {
        matchConfig.Name = lanBridge;
        networkConfig = {
          DHCP = "yes";
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
      "50-usb-cdc" = {
        matchConfig.Driver = "cdc_subset";
        networkConfig.Bridge = lanBridge;
        linkConfig.RequiredForOnline = "enslaved";
      };
    };
  };
}
