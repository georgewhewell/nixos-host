{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../../../profiles/common.nix
    # ../../../profiles/headless.nix
    ../../../profiles/home.nix
    ../../../profiles/pray-for-sd-card.nix
  ];

  sconfig = {
    profile = "server";
    home-manager.enable = true;
  };

  networking = {
    hostName = "neo2";
    useDHCP = true;
    useNetworkd = true;
  };

  documentation.enable = false;

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
                # mountOptions = [
                # "compress=zstd"
                # "noatime"
                # ];
              };
            };
          };
        };
      };
    };
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [
      "console=ttyS2,115200"
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

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  services.getty.autologinUser = "root";

  services.earlyoom = {
    enable = true;
    freeMemThreshold = 10;
    freeSwapThreshold = 10;
    enableNotifications = false;
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  deployment.targetHost = "192.168.23.84";
  deployment.targetUser = "grw";
}
