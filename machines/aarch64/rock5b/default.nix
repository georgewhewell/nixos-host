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
  iphoneWan = "iphone0";
  backupWan = network.vlans.wanBackup;
  backupTag = "backup${toString backupWan.id}";
  backupPeerIp = network.ipOf "wanBackup" network.hosts.bluefield2.addresses.wanBackup;
  backupPeerCidr = "${backupPeerIp}/32";
  backupAllowedSourceCidrs =
    map
      (name: "${network.primaryIp network.hosts.${name}}/32")
      network.policies.backupWan.allowedSourceHosts
    ++ network.policies.backupWan.additionalSourceCidrs
    ++ [ backupPeerCidr ];
  backupTcpPorts = lib.concatStringsSep "," (map toString network.policies.backupWan.tcpPorts);
  backupUdpPorts = lib.concatStringsSep "," (map toString network.policies.backupWan.udpPorts);
  backupForwardingRules = lib.concatMapStringsSep "\n" (source: ''
    iptables -w -t filter -A nixos-filter-forward -i '${backupTag}' -s '${source}' -o '${iphoneWan}' -p icmp -j ACCEPT
    iptables -w -t filter -A nixos-filter-forward -i '${backupTag}' -s '${source}' -o '${iphoneWan}' -p tcp -m multiport --dports '${backupTcpPorts}' -j ACCEPT
    iptables -w -t filter -A nixos-filter-forward -i '${backupTag}' -s '${source}' -o '${iphoneWan}' -p udp -m multiport --dports '${backupUdpPorts}' -j ACCEPT
    iptables -w -t nat -A nixos-nat-post -s '${source}' -o '${iphoneWan}' -j MASQUERADE
  '') backupAllowedSourceCidrs;
  backupRpfilterRules = lib.concatMapStringsSep "\n" (source: ''
    iptables -w -t mangle -I nixos-fw-rpfilter 1 -i '${backupTag}' -s '${source}' -j RETURN
  '') backupAllowedSourceCidrs;
  backupRoutingPolicyRules =
    map
      (source: {
        From = source;
        Table = backupWan.id;
        Priority = 10000 + backupWan.id;
        Family = "ipv4";
      })
      backupAllowedSourceCidrs
    ++ [
      {
        # Allows explicit Rock-local health checks bound to iphone0 without
        # depending on the DHCP address or gateway assigned by the handset.
        OutgoingInterface = iphoneWan;
        Table = backupWan.id;
        Priority = 9999 + backupWan.id;
        Family = "ipv4";
      }
    ];
  # Enabled after independently proving the USB lease and VLAN-101 transit.
  # Route injection remains a separate BlueField gate.
  backupForwardingEnable = true;
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
    ../../../services/hydra-builder-slave.nix
    ../../../services/kvm.nix
  ];

  deployment.targetHost = network.primaryIp self;
  deployment.targetUser = "grw";

  # Follow the OTG cable: a signed recovery UKI embeds its host identity.
  services.kvmBootstrap.targetHost = "strix-2";

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

  # Audio hardware only. The Spotify Connect endpoint that used to consume
  # it moved to the router (2026-08-20); the ES8316 3.5mm jack and the
  # PCM5102A on I2S2 are still wired to this board, so the ALSA config and
  # the DTS overlay stay. The kernel ASoC driver for ES8316 natively
  # supports up to S32_LE @ 96kHz — anything above that is ALSA plug-rate
  # resampling so we cap there.
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
    "/var/lib/kvm-bootstrap"
    "/var/lib/bluetooth"
    # Keep the iPhone trust record across the tmpfs root.  The USB Ethernet
    # function normally appears without manual pairing, but retaining lockdown
    # state avoids a trust prompt becoming a failover dependency.
    "/var/lib/lockdown"
  ];

  sconfig.impermanence.seedExisting.directories = [
    "/var/lib/bluetooth"
    "/var/lib/lockdown"
  ];

  # usbmuxd switches an attached iPhone into its multiplexed USB
  # configuration; the kernel ipheth driver provides the actual Ethernet
  # device.  Phase one intentionally gives only rock-5b itself a high-metric
  # IPv4 route.  Forwarding/NAT is added only after the lease is verified.
  services.usbmuxd.enable = true;

  networking = {
    hostName = "rock-5b";
    nameservers = [network.dnsIp];
    useNetworkd = true;

    useDHCP = false;
    nat = {
      enable = backupForwardingEnable;
      enableIPv6 = false;
      externalInterface = iphoneWan;
      # The NixOS NAT module turns either of these into an unrestricted
      # forwarding ACCEPT. Keep them empty and install the narrow policy below.
      internalInterfaces = [ ];
      internalIPs = [ ];
      extraCommands = ''
        ${backupForwardingRules}
        # Never let rejected BlueField transit escape through Rock's primary
        # wired default, even if a future route or rpfilter change would permit
        # it. Then fail closed for every other phone-bound source/protocol.
        iptables -w -t filter -A nixos-filter-forward -i '${backupTag}' -j DROP
        iptables -w -t filter -A nixos-filter-forward -o '${iphoneWan}' -j DROP
      '';
    };
    firewall.enable = true;

    wireless.interfaces = ["wlP2p33s0f0"];
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;

    links."10-iphone-tether" = {
      matchConfig.Driver = "ipheth";
      linkConfig.Name = iphoneWan;
    };

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
      # Dedicated control-only transit to BlueField VPP.
      "30-${backupTag}" = {
        netdevConfig = {
          Kind = "vlan";
          Name = backupTag;
        };
        vlanConfig.Id = backupWan.id;
      };
    };

    networks = {
      # eth trunk: rock-5b's own mgmt IP sits directly on the NIC (untagged);
      # the tagged wifi VLAN rides the same wire (see 30-${wifiTag}).
      "10-lan" = {
        matchConfig.Driver = "r8169";
        vlan = [ wifiTag backupTag ];
        address = [(network.cidrOf "lan" self.addresses.lan)];
        dns = [network.dnsIp];
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

      "30-${backupTag}" = {
        matchConfig.Name = backupTag;
        address = [ (network.cidrOf "wanBackup" self.addresses.wanBackup) ];
        routes = map (destination: {
          Destination = destination;
          Gateway = backupPeerIp;
          GatewayOnLink = true;
        }) network.policies.backupWan.vppTestReturnCidrs;
        networkConfig = {
          ConfigureWithoutCarrier = true;
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
        };
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

      # iPhone Personal Hotspot.  Do not consume its DNS and keep its default
      # well below wired/Wi-Fi while the primary WAN exists.  IPv6 stays off
      # until we have observed the provider behaviour; there is no NAT66
      # fallback hidden here.
      "60-iphone-tether" = {
        matchConfig.Name = iphoneWan;
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
          DNSDefaultRoute = false;
        };
        dhcpV4Config = {
          UseDNS = false;
          UseRoutes = true;
          RouteMetric = 4096;
          # Keep the DHCP-derived cellular gateway in its own table. Approved
          # transit sources select it below; no leased address is hardcoded.
          RouteTable = backupWan.id;
        };
        routingPolicyRules = backupRoutingPolicyRules;
        linkConfig.RequiredForOnline = "no";
      };
    };
  };

  # Several local services open ports globally through NixOS module options.
  # Insert this before those accepts so none of them become reachable through
  # the untrusted tether.  Replies to connections initiated by rock-5b remain
  # possible; new inbound traffic from the iPhone is dropped.
  networking.firewall.extraCommands = lib.mkAfter ''
    # Replies arriving on the deliberately high-metric phone fail strict
    # reverse-path validation because the same remote is normally reachable
    # through wired LAN. Bypass rpfilter only on this interface; the input and
    # forward rules below remain the actual trust boundary.
    iptables -t mangle -I nixos-fw-rpfilter 1 -i ${iphoneWan} -j RETURN

    # Transit reaches Rock through BlueField, so strict rpfilter cannot infer
    # the intended asymmetric path from the ordinary LAN routes. Exempt only
    # the source CIDRs admitted by the phone-egress policy; all other sources
    # still hit strict rpfilter before the input/forward chains.
    ${backupRpfilterRules}

    # DHCP is the only new inbound IPv4 flow the phone may initiate toward the
    # host. Everything else must be a reply to Rock's own traffic.
    iptables -I nixos-fw 1 -i ${iphoneWan} -p udp --sport 67 --dport 68 -j nixos-fw-accept
    iptables -I nixos-fw 2 -i ${iphoneWan} -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept
    iptables -I nixos-fw 3 -i ${iphoneWan} -j nixos-fw-refuse
    ip6tables -I nixos-fw 1 -i ${iphoneWan} -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept
    ip6tables -I nixos-fw 2 -i ${iphoneWan} -j nixos-fw-refuse

    # Rock's own processes get the same control-plane-only boundary. Forwarded
    # traffic is governed separately by nixos-filter-forward above.
    iptables -I OUTPUT 1 -o ${iphoneWan} -p udp --sport 68 --dport 67 -j ACCEPT
    iptables -I OUTPUT 2 -o ${iphoneWan} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -I OUTPUT 3 -o ${iphoneWan} -p icmp -j ACCEPT
    iptables -I OUTPUT 4 -o ${iphoneWan} -p tcp -m multiport --dports ${backupTcpPorts} -j ACCEPT
    iptables -I OUTPUT 5 -o ${iphoneWan} -p udp -m multiport --dports ${backupUdpPorts} -j ACCEPT
    iptables -I OUTPUT 6 -o ${iphoneWan} -j DROP
    ip6tables -I OUTPUT 1 -o ${iphoneWan} -j DROP

    # VLAN 101 is a small control transit. Until switch filtering is enabled,
    # explicitly distrust every host other than the BlueField router peer.
    iptables -I nixos-fw 4 -i ${backupTag} -s ${backupPeerCidr} -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept
    iptables -I nixos-fw 5 -i ${backupTag} -s ${backupPeerCidr} -p icmp -j nixos-fw-accept
    iptables -I nixos-fw 6 -i ${backupTag} -s ${backupPeerCidr} -p tcp --dport 22 -j nixos-fw-accept
    iptables -I nixos-fw 7 -i ${backupTag} -j nixos-fw-refuse
    ip6tables -I nixos-fw 3 -i ${backupTag} -j nixos-fw-refuse
  '';

  environment.systemPackages = with pkgs; [
    # Pairing/diagnostic CLI for the backup-WAN iPhone. usbmuxd already pulls
    # the library into the closure, but not these user-facing tools onto PATH.
    libimobiledevice
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

  # GPS moved to k3 (2026-08-11), which has the receiver on its own UART; gpsd
  # went with it via services/gps.nix. This host's gpsd pointed at
  # `tcp://esp32-p4-eth-01:8888`, an ESP32 UART-to-TCP bridge that no longer
  # has a receiver attached, so it would have polled a dead socket forever.
  #
  # The 40-pin wiring this board would need, kept for whenever a receiver
  # comes back to it:
  #   GPS TX  → Pin 10 (UART2_RX_M0, GPIO0_B6)
  #   GPS RX  → Pin 8  (UART2_TX_M0, GPIO0_B5)
  #   GPS PPS → Pin 16 (GPIO3_A4) - requires DT overlay
  #   GPS VCC → Pin 1 or 17 (3.3V)
  #   GPS GND → Pin 6, 9, 14, or 20 (GND)

  # PPS (Pulse Per Second) support for precise timing
  boot.kernelModules = [
    "pps-gpio"
    "ipheth"
  ];

  # Device tree for Rock 5B
  # EDK2 first loads `\dtb\<PcdDeviceTreeName>.dtb` from the ESP when the
  # FdtOverrideBasePath efivar is set. systemd-boot's BLS `devicetree` entry
  # then replaces the FDT passed to Linux. Keep the fixed firmware fallback
  # synchronized with the same merged DTB on every switch/boot.
  hardware.deviceTree = {
    enable = true;
    name = "rockchip/rk3588-rock-5b.dtb";
    overlays = [
      {
        name = "rk3588-i2s2-pcm5102a";
        dtsFile = ./i2s2-pcm5102a.dts;
      }
      {
        name = "rk3588-pex88096-pcie3x4";
        dtsFile = ./pex88096-pcie3x4.dts;
        filter = "rockchip/rk3588-rock-5b.dtb";
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

  # 1234 (spotifyd zeroconf) and 5353 (its libmdns responder) closed with the
  # move to the router — nothing else on this host announces over mDNS.
  # KVM/mediamtx ports come from services/kvm.nix.

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
