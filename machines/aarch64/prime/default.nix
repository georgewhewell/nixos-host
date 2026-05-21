{
  config,
  pkgs,
  lib,
  modulesPath,
  inputs,
  network,
  ...
}: {
  system.stateVersion = "25.05";

  imports = [
    inputs.disko.nixosModules.disko
    ../../../profiles/common.nix
    ../../../profiles/headless.nix
    ../../../profiles/home.nix
    ../../../profiles/pray-for-sd-card.nix
    ../../../services/buildfarm-slave.nix
  ];

  deployment.targetHost = "prime.${network.domains.lan}";
  deployment.targetUser = "grw";

  sconfig = {
    profile = "server";
    home-manager.enable = false;
  };

  networking = {
    hostName = "prime";
    useDHCP = true;
    useNetworkd = true;
  };

  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/mmcblk0";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              name = "ESP";
              start = "1M";
              size = "512M";
              type = "EF00";
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

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    extraModprobeConfig = ''
      options cfg80211 ieee80211_regdom="CH"
    '';

    kernelParams = [
      "console=ttyS0,115200"
    ];

    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
      timeout = 1;
    };

    initrd = {
      systemd = {
        enable = true;
        emergencyAccess = true;
        network.enable = true;
      };

      kernelModules = [
        "dwmac_sun8i"
        "sun8i_a33_mbus"
      ];

      availableKernelModules = [
        "sunxi"
        "musb_hdrc"
        "sun6i_dma"
        "ehci-platform"
        "zstd"
        "zstd_compress"
        "cdc_ether"
        "r8152"
        "stmmac"
        "dwmac_sun8i"
      ];
    };
  };

  hardware = {
    wirelessRegulatoryDatabase = true;
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };

  services.getty.autologinUser = "root";

  services.earlyoom = {
    enable = true;
    freeMemThreshold = 10;
    freeSwapThreshold = 10;
    enableNotifications = false;
  };

  nix = {
    settings = {
      build-cores = 2;
      max-jobs = 1;
      http-connections = 2;
    };
  };

  # zramSwap = {
  #   enable = true;
  #   algorithm = "zstd";
  #   memoryPercent = 50;
  # };
}
