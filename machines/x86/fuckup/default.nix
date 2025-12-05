{
  pkgs,
  lib,
  inputs,
  modulesPath,
  ...
}: {
  /*
  AMD Ryzen 9 9950X3D
  */
  sconfig = {
    profile = "server";
    home-manager.enable = true;
    xmrig = with pkgs; {
      enable = true;
      package = xmrig-zen5;
      cudaPlugin = xmrig-cuda-plugin;
    };
  };

  system.stateVersion = "25.05";

  deployment.targetHost = "fuckup.lan.satanic.link";
  deployment.targetUser = "grw";

  boot.tmp.useTmpfs = lib.mkForce false;

  hardware.enableAllHardware = true;
  nix.settings.system-features = ["gccarch-znver5"];

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd
    common-gpu-amd

    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/headless.nix
    ../../../profiles/radeon.nix
    ../../../profiles/nvidia.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/zfs.nix
    ../../../profiles/development.nix
    ../../../profiles/wireless.nix

    ../../../services/buildfarm-slave.nix

    inputs.nix-llamacpp-rocm.nixosModules.default
    inputs.nix-llamacpp-rocm.nixosModules.benchmark-runner
    inputs.nix-llamacpp-rocm.nixosModules.tuning
  ];

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

  environment.systemPackages = with pkgs; [
    wirelesstools
    iw
    gpu-burn
    geekbench_6
    passmark-performancetest

    (python3.withPackages (ps:
      with ps; [
        hf-transfer
        huggingface-hub

        # (huggingface-hub.extras ["hf_transfer"])
      ]))
  ];

  services.hardware.bolt.enable = true;

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
    useDHCP = true;
  };
}
