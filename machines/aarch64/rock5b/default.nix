{
  config,
  pkgs,
  lib,
  inputs,
  network,
  ...
}: let
  self = network.hosts."rock-5b";
  persist = config.sconfig.impermanence.persistentStoragePath;
  # eth is the trunk: untagged carries rock-5b's own LAN mgmt IP; tagged
  # carries the wifi client VLAN. hostapd bridges wlan0 into br0.lan, whose
  # only uplink is this tagged subiface, so wifi clients egress eth tagged
  # and are routed/DHCP'd by the router on the wifi VLAN.
  wifiTag = "wifi${toString network.vlans.wifi.id}";
in {
  system.stateVersion = "25.05";

  imports = [
    inputs.disko.nixosModules.disko
    ../../../profiles/common.nix
    # ../../../profiles/headless.nix
    ../../../profiles/home.nix
    ../../../profiles/pray-for-sd-card.nix
    ../../../profiles/wireless.nix
    ../../../profiles/router/ap.nix
    ../../../services/buildfarm-slave.nix
    ../../../services/kvm.nix
  ];

  deployment.targetHost = network.primaryIp self;
  deployment.targetUser = "grw";

  sconfig = {
    profile = "server";
    home-manager.enable = true;
    impermanence = {
      enable = true;
      # Keep the existing eMMC btrfs root intact and mount it at /persist.
      # Existing impermanence data then lives under /persist/persist.
      persistentStoragePath = "/persist/persist";
    };
    xmrig = {
      enable = false;
      package = pkgs.xmrig-rock5b;
    };
  };

  # Minimal closure optimizations
  nix.registry = lib.mkForce {}; # Don't pin nixpkgs source in closure

  disko.imageBuilder.enableBinfmt = true;
  disko.devices = {
    disk = {
      rock5b-emmc = {
        device = "/dev/mmcblk0";
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
                format = "btrfs";
                mountpoint = "/persist";
                mountOptions = ["compress=zstd:1" "noatime"];
              };
            };
          };
        };
      };
    };
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "size=2G"
        "defaults"
        "mode=755"
      ];
    };
  };

  fileSystems."/" = {
    neededForBoot = true;
  };

  fileSystems."/persist" = {
    neededForBoot = true;
  };

  fileSystems."/nix" = {
    device = "/persist/nix";
    fsType = "none";
    options = ["bind"];
    depends = ["/persist"];
    neededForBoot = true;
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    extraModprobeConfig = ''
      options cfg80211 ieee80211_regdom="CH"
      options iwlwifi power_save=1 11n_disable=1
      options iwlmvm power_scheme=1
    '';
    kernelParams = [
      # Force HDMI output for loopback capture
      "video=HDMI-A-1:640x480@60e"
    ];
    loader = {
      grub.enable = false;
      systemd-boot = {
        enable = true;
        configurationLimit = 4;
        installDeviceTree = true; # Load NixOS DTB with overlays instead of UEFI DTB
      };
      efi.canTouchEfiVariables = true;
      timeout = 1;
    };
    initrd = {
      systemd = {
        enable = true;
        emergencyAccess = true;
        network.enable = true;
      };

      kernelModules = [
        "r8169"
        "phy_rockchip_naneng_combphy"
      ];

      availableKernelModules = [
        "phy_rockchip_naneng_combphy"
        "mmc_core"
        "mmc_block"
      ];
    };
  };

  # NVMe boot support (uncomment if booting from NVMe)
  # boot.kernelParams = [ "pcie_aspm=off" ];
  # boot.initrd.kernelModules = [ "nvme" ];
  # boot.initrd.systemd.services.pcie-rescan = {
  #   description = "Rescan PCIe bus for NVMe detection";
  #   after = [ "modprobe@nvme.service" ];
  #   before = [ "systemd-udev-settle.service" ];
  #   wantedBy = [ "initrd.target" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.bash}/bin/bash -c 'echo 1 > /sys/bus/pci/rescan && sleep 2'";
  #     RemainAfterExit = true;
  #   };
  # };

  services.udev.extraRules = ''
    # Disable EEE when r8169 ethernet interface comes up
    ACTION=="add", SUBSYSTEM=="net", DRIVERS=="r8169", RUN+="${pkgs.ethtool}/bin/ethtool --set-eee $name eee off"

    # Disable power save on WiFi interfaces
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="wlan*", RUN+="${pkgs.iw}/bin/iw dev $name set power_save off"
  '';

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  # Spotify Connect endpoint (moved here from prime). Analog out goes
  # through the on-board ES8316 codec (3.5mm jack). The kernel ASoC
  # driver for ES8316 natively supports up to S32_LE @ 96kHz — anything
  # above that is ALSA plug-rate resampling so we cap there.
  # zeroconf_port pinned for the firewall holes below.
  hardware.alsa = {
    enable = true;
    config = ''
      defaults.pcm.card 0
      defaults.ctl.card 0

      pcm.!default {
        type plug
        slave.pcm "highquality"
      }

      pcm.highquality {
        type hw
        card 0
        device 0
        format S32_LE
        rate 96000
      }

      # PCM5102A on I2S2_M1: force 48 kHz so the RK3588 audio PLL divides
      # cleanly (393.22 MHz / 32 = 12.288 MHz = 256 × 48 kHz). At 44.1 kHz
      # the fractional divider introduces jitter the PCM5102A's internal PLL
      # struggles to lock. ALSA's plug plugin resamples upstream rates.
      pcm.pcm5102a {
        type plug
        slave {
          pcm "hw:CARD=rockchippcm5102,DEV=0"
          format S32_LE
          rate 48000
          channels 2
        }
      }
    '';
  };

  services.spotifyd = {
    enable = true;
    settings.global = {
      device_name = "rock-5b";
      device_type = "speaker";
      use_mpris = false;
      dbus_type = "system";
      cache_path = "/tmp/spotifyd";
      max_cache_size = 100000000; # ~100MB
      disable_discovery = false;
      zeroconf_port = 1234;
      backend = "alsa";
      device = "pcm5102a";
      volume_controller = "softvol";
      initial_volume = 10;
      audio_format = "S32";
      bitrate = 320;
    };
  };

  # Unmute the ES8316 Headphone output and set to max (range 0-3).
  # Without this the codec boots at 33% / -24dB which is inaudible.
  systemd.services.configure-es8316 = {
    description = "Unmute and level the on-board ES8316 headphone output";
    after = ["sound.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "-${pkgs.alsa-utils}/bin/amixer -c 0 sset 'Headphone' 3 unmute"
        "-${pkgs.alsa-utils}/bin/amixer -c 0 sset 'Headphone Mixer' 11"
      ];
    };
  };

  hardware = {
    wirelessRegulatoryDatabase = true;
    # Minimal firmware - only Intel WiFi 7 BE200 and Intel Bluetooth
    enableAllFirmware = lib.mkDefault true;
    # enableRedistributableFirmware = lib.mkForce false;
    firmware = [
      #   (pkgs.runCommand "minimal-firmware" {} ''
      #     mkdir -p $out/lib/firmware/intel $out/lib/firmware/arm/mali/arch10.8
      #     # Intel WiFi 7 BE200 firmware (all versions + pnvm)
      #     cp -L ${pkgs.linux-firmware}/lib/firmware/iwlwifi-gl-c0-fm-c0-*.ucode $out/lib/firmware/
      #     cp -L ${pkgs.linux-firmware}/lib/firmware/iwlwifi-gl-c0-fm-c0.pnvm $out/lib/firmware/
      #     # Intel Bluetooth firmware (sfi + ddc)
      #     cp -L ${pkgs.linux-firmware}/lib/firmware/intel/ibt-0291-0291.sfi $out/lib/firmware/intel/
      #     cp -L ${pkgs.linux-firmware}/lib/firmware/intel/ibt-0291-0291.ddc $out/lib/firmware/intel/
      #     # Mali G610 (Panthor) CSF firmware
      #     cp -L ${pkgs.linux-firmware}/lib/firmware/arm/mali/arch10.8/mali_csffw.bin $out/lib/firmware/arm/mali/arch10.8/
      #   '')
    ];
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };

  environment.persistence.${persist}.directories = [
    "/var/lib/bluetooth"
  ];

  sconfig.impermanence.seedExisting.directories = [
    "/var/lib/bluetooth"
  ];

  networking = {
    hostName = "rock-5b";
    nameservers = [network.routerIp];
    useNetworkd = true;

    useDHCP = false;
    nat.enable = false;
    firewall.enable = true;

    wireless.interfaces = ["wlP2p33s0f0"];
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;

    netdevs = {
      # AP bridge: hostapd's wlan0 + the tagged wifi uplink.
      "10-br0.lan" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br0.lan";
        };
        bridgeConfig.STP = false;
      };
      # Tagged wifi VLAN on the eth trunk; joins the AP bridge.
      "30-${wifiTag}" = {
        netdevConfig = {
          Kind = "vlan";
          Name = wifiTag;
        };
        vlanConfig.Id = network.vlans.wifi.id;
      };
    };

    networks = {
      # eth trunk: rock-5b's own mgmt IP sits directly on the NIC (untagged);
      # the tagged wifi VLAN rides the same wire (see 30-${wifiTag}).
      "10-lan" = {
        matchConfig.Driver = "r8169";
        vlan = [wifiTag];
        address = [(network.cidrOf "lan" self.addresses.lan)];
        dns = [network.routerIp];
        routes = [
          {
            Gateway = network.routerIp;
            Metric = 1;
          }
        ];
        # Do not keep the LAN address/routes installed while the wired link is
        # down. Otherwise WiFi fallback receives traffic, but replies to LAN
        # hosts are sent to the dead Ethernet interface.
        networkConfig.ConfigureWithoutCarrier = false;
        linkConfig.RequiredForOnline = "routable";
      };

      # Tagged wifi VLAN -> AP bridge.
      "30-${wifiTag}" = {
        matchConfig.Name = wifiTag;
        networkConfig.Bridge = "br0.lan";
        linkConfig.RequiredForOnline = "no";
      };

      # AP bridge has no host IP — it only joins wlan0 (via hostapd) to the
      # tagged wifi uplink, keeping wifi clients off rock-5b's LAN mgmt.
      "10-br0.lan" = {
        matchConfig.Name = "br0.lan";
        networkConfig.ConfigureWithoutCarrier = true;
        linkConfig.RequiredForOnline = "no";
      };

      # Intel iwlwifi - client mode with DHCP (fallback)
      "20-wifi-client" = {
        matchConfig.Driver = "iwlwifi";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config = {
          Hostname = "rock-5b-wifi";
          RouteMetric = 200;
        };
        linkConfig.RequiredForOnline = "no";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    iperf
    lshw
    pciutils
    usbutils
    wirelesstools
    iw
    iwd
    powertop
    stress-ng
    v4l-utils
    ffmpeg-headless
    gpsd # GPS tools: cgps, gpsmon, gpspipe
    pps-tools # PPS testing: ppstest, ppswatch
    # xmrig
  ];

  # GPS module on UART2 (40-pin header pins 8/10)
  # Wiring:
  #   GPS TX  → Pin 10 (UART2_RX_M0, GPIO0_B6)
  #   GPS RX  → Pin 8  (UART2_TX_M0, GPIO0_B5)
  #   GPS PPS → Pin 16 (GPIO3_A4) - requires DT overlay
  #   GPS VCC → Pin 1 or 17 (3.3V)
  #   GPS GND → Pin 6, 9, 14, or 20 (GND)
  services.gpsd = {
    enable = true;
    devices = ["tcp://esp32-p4-eth-01.${network.domains.lan}:8888"];
    readonly = false;
    extraArgs = ["-n"]; # Don't wait for client connect to poll GPS
  };

  # PPS (Pulse Per Second) support for precise timing
  boot.kernelModules = ["pps-gpio"];

  # Device tree for Rock 5B
  # EDK2 UEFI ignores systemd-boot's devicetree directive — it loads
  # `\dtb\<PcdDeviceTreeName>.dtb` from the ESP when FdtOverrideBasePath
  # efivar is set (see edk2-rockchip FdtPlatformDxe). The activation
  # script below syncs the merged DTB to that path on every switch/boot.
  hardware.deviceTree = {
    enable = true;
    name = "rockchip/rk3588-rock-5b.dtb";
    overlays = [
      {
        name = "rk3588-i2s2-pcm5102a";
        dtsFile = ./i2s2-pcm5102a.dts;
      }
    ];
  };

  system.activationScripts.fdt-override-sync.text = ''
    src=/run/current-system/dtbs/rockchip/rk3588-rock-5b.dtb
    dst=/boot/dtb/rk3588-rock-5b.dtb
    if [ -f "$src" ]; then
      mkdir -p /boot/dtb
      if ! cmp -s "$src" "$dst" 2>/dev/null; then
        cp "$src" "$dst.new"
        mv "$dst.new" "$dst"
        echo "fdt-override-sync: updated $dst"
      fi
    fi
  '';

  # spotifyd zeroconf (1234) + mDNS (5353); KVM/mediamtx ports come from services/kvm.nix
  networking.firewall.allowedTCPPorts = [1234];
  networking.firewall.allowedUDPPorts = [5353];

  services.irqbalance.enable = lib.mkDefault true;

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "ondemand";
    # powertop.enable = true;
  };

  services.getty.autologinUser = "root";

  services.earlyoom = {
    enable = true;
    freeMemThreshold = 10;
    freeSwapThreshold = 10;
    enableNotifications = false;
  };

  zramSwap = {
    enable = false;
    algorithm = "zstd";
    memoryPercent = 50;
  };
}
