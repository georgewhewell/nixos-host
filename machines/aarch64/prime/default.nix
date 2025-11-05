{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    ../../../profiles/common.nix
    ../../../profiles/headless.nix
    ../../../profiles/home.nix
    ../../../profiles/pray-for-sd-card.nix
  ];

  sconfig = {
    profile = "server";
    home-manager.enable = true;
  };

  networking.firewall.allowedUDPPorts = [
    5353
  ];
  networking.firewall.allowedTCPPorts = [
    1234
  ];

  services.spotifyd = {
    enable = true;
    settings = {
      global = {
        device_name = "prime";
        device_type = "speaker";
        use_mpris = false;
        dbus_type = "system";
        cache_path = "/tmp/spotifyd";
        max_cache_size = 100000000; # ~100MB
        # };
        # discovery = {
        disable_discovery = false;
        zeroconf_port = 1234;
        # };
        # audio = {
        backend = "alsa";
      };
    };
  };

  deployment.targetHost = "prime.lan.satanic.link";
  deployment.targetUser = "grw";

  networking = {
    hostName = "prime";
    useDHCP = true;
    useNetworkd = true;
  };

  hardware.alsa.enable = true;

  # Set REIYIN Audio device as default
  hardware.alsa.config = ''
    defaults.pcm.card 0
    defaults.ctl.card 0
  '';

  # Run amixer commands after boot to configure audio
  systemd.services.configure-usb-audio = {
    description = "Configure USB audio device for analog output";
    after = ["sound.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "${pkgs.alsa-utils}/bin/amixer -c 0 set 'REIYIN Audio' unmute"
        "${pkgs.alsa-utils}/bin/amixer -c 0 set 'Extension Unit' off"
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    btop
  ];

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

  services.iperf3 = {
    enable = true;
    openFirewall = true;
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

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };
}
