{
  config,
  pkgs,
  lib,
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

  deployment.targetHost = "neo2.${network.domains.lan}";
  deployment.targetUser = "grw";

  sconfig = {
    profile = "server";
    home-manager.enable = true;
  };

  networking = {
    hostName = "neo2";
    useDHCP = true;
    useNetworkd = true;
  };

  disko.imageBuilder.enableBinfmt = true;
  disko.devices = {
    disk = {
      neo2-sdcard = {
        device = "/dev/sda";
        type = "disk";
        imageSize = "2G";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "512M";
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
        # Write u-boot to sector 256 (128KB offset) for Allwinner H3+ SoCs
        # This location doesn't conflict with GPT partition table
        postCreateHook = ''
          dd if=${pkgs.ubootNanoPiNeo2}/u-boot-sunxi-with-spl.bin of=$device bs=1024 seek=128 conv=notrunc
        '';
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
