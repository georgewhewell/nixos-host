{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../../../profiles/common.nix
    ../../../profiles/headless.nix
    ../../../profiles/home.nix
    ../../../profiles/pray-for-sd-card.nix
    ../../../services/buildfarm-slave.nix
  ];

  deployment.targetHost = "neo2.lan.satanic.link";
  deployment.targetUser = "grw";

  sconfig = {
    profile = "server";
    home-manager.enable = false;
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

  # USB OTG Ethernet gadget
  boot.kernelModules = ["g_ether"];

  # Use udev rule to set peripheral mode automatically
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="platform", KERNEL=="musb-hdrc.2.auto", RUN+="${pkgs.bash}/bin/sh -c 'echo peripheral > /sys/devices/platform/soc/1c19000.usb/musb-hdrc.2.auto/mode'"
  '';

  systemd.network.networks."10-usb0" = {
    matchConfig.Name = "usb0";
    networkConfig = {
      DHCP = "yes";
      IPv6AcceptRA = true;
    };
  };

  services.getty.autologinUser = "root";

  services.earlyoom = {
    enable = true;
    freeMemThreshold = 10;
    freeSwapThreshold = 10;
    enableNotifications = false;
  };

  # zramSwap = {
  #   enable = true;
  #   algorithm = "zstd";
  #   memoryPercent = 50;
  # };
}
