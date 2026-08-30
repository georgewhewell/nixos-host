{ inputs
, config
, lib
, pkgs
, network
, ...
}: let
  spotifydNetns = "spotifyd";
  spotifydInterface = "spotifyd0";
  spotifydHost = network.hosts.spotifyd;
  spotifydWifiIp = network.primaryIp spotifydHost;
  spotifydResolvConf = pkgs.writeText "spotifyd-resolv.conf" ''
    nameserver 1.1.1.1
    nameserver 2606:4700:4700::1111
  '';
in {
  /*
    router: cwwk 8845hs board
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableVscodeServer = false;
    };
  };

  # Bind to the LAN bridge IP only — never 0.0.0.0 since this host
  # holds the public WAN address too. `openFirewall` would open port
  # 6052 globally, so leave it off and add a LAN-scoped rule instead.
  services.esphome-dashboard = {
    enable = true;
    # Keep this on the legacy address until the application-service phase;
    # the phase-one deploy only establishes .31 for DNS/DHCP/netboot.
    address = network.routerIp;
  };
  networking.firewall.interfaces."br0.lan".allowedTCPPorts = [
    6052 # esphome-dashboard
  ];
  # Spotifyd's zeroconf listener lives only inside its WiFi macvlan namespace;
  # it never binds a socket in the router's host namespace.

  # Spotify Connect endpoint, moved off rock-5b 2026-08-20. Output is the
  # board's ALC269VC analog jack (PCI c9:00.6), not the GPU's HDMI audio
  # function (c9:00.1) — both are snd_hda_intel and both register as
  # "Generic", so pin the card ids by probe order and address the DAC by
  # name. profiles/headless.nix defaults hardware.alsa off; override it.
  hardware.alsa = {
    enable = true;
    # The mixer state below is declarative; don't let a saved state file
    # from /var/lib/alsa race the unmute service and win.
    enablePersistence = false;
    config = ''
      pcm.analogout {
        type plug
        slave.pcm "hw:CARD=analog,DEV=0"
      }
    '';
  };

  services.spotifyd = {
    enable = true;
    settings.global = {
      device_name = "HiFi";
      device_type = "speaker";
      use_mpris = false;
      max_cache_size = 100000000; # ~100MB; the module pins /var/cache/spotifyd
      # A fixed port makes the namespace boundary observable and testable.
      # The host firewall does not expose it because the listener exists only
      # on spotifyd0 inside the namespace.
      zeroconf_port = 1234;
      backend = "alsa";
      device = "analogout";
      volume_controller = "softvol";
      initial_volume = 10;
      audio_format = "S16";
      bitrate = 320;
    };
  };

  # libmdns has no interface selector and advertises every address visible to
  # the process. On the multi-homed router that previously included public WAN,
  # host-PF and RShim addresses, while the WiFi VLAN was absent. Put spotifyd
  # in a namespace with one macvlan instead: discovery is emitted directly on
  # VLAN 50 as 192.168.50.30, and Avahi remains the sole responder in the host
  # namespace. The namespace uses public resolvers because a macvlan child
  # cannot reach services bound to its host parent (192.168.50.31).
  systemd.services.spotifyd-netns = {
    description = "Create the WiFi-only spotifyd network namespace";
    before = ["spotifyd.service"];
    requiredBy = ["spotifyd.service"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.iproute2];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "-${pkgs.iproute2}/bin/ip netns delete ${spotifydNetns}";
    };
    script = ''
      ip netns delete ${spotifydNetns} 2>/dev/null || true
      ip netns add ${spotifydNetns}

      ip link add link br0.lan.50 name ${spotifydInterface} type macvlan mode bridge
      ip link set dev ${spotifydInterface} address ${spotifydHost.mac}
      ip link set dev ${spotifydInterface} netns ${spotifydNetns}

      ip netns exec ${spotifydNetns} ip link set dev lo up
      ip netns exec ${spotifydNetns} ip address add ${spotifydWifiIp}/${toString network.vlans.wifi.cidr} dev ${spotifydInterface}
      ip netns exec ${spotifydNetns} ip link set dev ${spotifydInterface} up
      ip netns exec ${spotifydNetns} ip route replace default via ${network.gatewayIp "wifi"}
    '';
  };

  systemd.services.spotifyd = {
    requires = ["spotifyd-netns.service"];
    after = ["spotifyd-netns.service"];
    serviceConfig = {
      NetworkNamespacePath = "/run/netns/${spotifydNetns}";
      BindReadOnlyPaths = ["${spotifydResolvConf}:/etc/resolv.conf"];
    };
  };

  # The ALC269VC comes up with Master at 0/87 and muted, which is silence with
  # no error anywhere. Pin it; spotifyd's softvol does the actual volume.
  systemd.services.configure-alc269 = {
    description = "Unmute and level the on-board ALC269VC analog output";
    after = ["sound.target"];
    wantedBy = ["multi-user.target"];
    before = ["spotifyd.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "-${pkgs.alsa-utils}/bin/amixer -c analog sset Master 80% unmute"
      ];
    };
  };

  # Pin the router to the explicit RC package set instead of following
  # nixpkgs' moving linuxPackages_latest from profiles/uefi-boot.nix.
  boot.kernelPackages = lib.mkForce pkgs.linuxKernel.packages.linux_7_2_rc2;

  # Realtek RTL8127 10GbE out-of-tree driver with RSS/multi-queue support
  # The in-kernel r8169 driver only has single-queue support for this chip
  boot.extraModulePackages = lib.mkIf config.router.legacyPcieNetwork.enable [
    (config.boot.kernelPackages.callPackage ../../../packages/r8127 { })
  ];
  boot.blacklistedKernelModules = lib.mkIf config.router.legacyPcieNetwork.enable [ "r8169" ];

  boot.kernelParams = [
    # "video=HDMI-A-1:1920x1080@60e" # 'e' forces enable even without EDID
    "iommu=pt"
    # ACPI reboot reached systemd-shutdown but did not reset the board
    # (AMI FMA01_P5C9V10, 2026-06-15). Use the chipset reset path instead.
    "reboot=pci"
  ];

  deployment.targetHost = network.domains.public;
  deployment.targetUser = "grw";

  system.stateVersion = "24.11";

  sconfig.gcp-ddns = {
    enable = true;
    aRecords = [ network.domains.public ];
    aaaaRecords = [ network.domains.public ];
  };

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd
    common-gpu-amd

    inputs.nix-strix-halo.nixosModules.default
    inputs.nix-strix-halo.nixosModules.ryzenadj

    ../../../profiles/headless.nix
    ../../../profiles/bluefield-host.nix
    ../../../profiles/bluefield-hostpf.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/radeon.nix
    ../../../profiles/zfs.nix
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/router/linux.nix
    ../../../profiles/router/services.nix
    ../../../profiles/router/usb-btrfs.nix
    # ../../../profiles/router/ap.nix  # WiFi card not installed
    ../../../profiles/router/wireguard.nix

    ../../../services/buildfarm-slave.nix
    # UniFi controller removed 2026-06-14 — the last UniFi device (AC-Pro) now
    # runs OpenWrt, so the controller is no longer needed.
    ../../../services/home-assistant/default.nix
    ../../../services/go2rtc.nix
    # Frigate (recording/detection) is still parked pending a decision on which
    # host should own it — go2rtc above is what HA needs for live camera views.
    # ../../../services/frigate.nix
  ];

  hardware.cpu.amd.ryzen-smu.enable = true;
  programs.ryzen-monitor-ng.enable = true;

  # Declaratively authorize the IOCREST USB4 10GbE enclosure (atlantic,
  # br0.lan port). Domain security is "user" and boltd's authorization store
  # (/var/lib/boltd) doesn't survive impermanence, so without this the NIC
  # stays unauthorized after every boot/re-plug and its LAN segment goes dark.
  services.udev.extraRules = lib.mkIf config.router.legacyPcieNetwork.enable ''
    ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{unique_id}=="c8010000-00b1-bd08-2230-ad1cc6200123", ATTR{authorized}=="0", ATTR{authorized}="1"
  '';

  environment.systemPackages = with pkgs;
    [ryzenadj uhubctl]
    ++ lib.optionals config.router.legacyPcieNetwork.enable [mstflint rdma-core perftest];

  # hardware."thunderbolt-ibverbs" = {
  #   blacklist.enable = true;
  #   loadOnBoot = true;

  #   config = {
  #     profile = "mac_compat";
  #     compat = "force";
  #     tbnet = "block";
  #     tbnet_identity = "minimal_packet";
  #     tbnet_identity_minimal_e2e = true;
  #     tbnet_identity_minimal_apple_only = true;
  #     roce_netdev = "ardma0";
  #     lanes = "1";
  #     bind_services = true;
  #     allocate_rings = true;
  #     start_rings = true;
  #     negotiate_native = false;
  #     enable_tunnels = true;
  #     native_data = false;
  #     native_fragment_striping = false;
  #     apple_data = true;
  #     register_verbs = true;
  #   };
  # };

  # services.ryzenadj = {
  #   enable = true;
  #   # stapmLimit = 30000;
  #   fastLimit = 45000;
  #   slowLimit = 38000;
  #   tctlTemp = 90;
  # };

  systemd.network.networks."20-nanokvm" = {
    matchConfig = {
      Driver = "cdc_ether";
      MACAddress = "02:1a:11:00:01:02";
    };
    address = [
      "10.55.0.2/24"
    ];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      IPv6PrivacyExtensions = false;
      IPv6Forwarding = false;
      IgnoreCarrierLoss = true;
    };
    linkConfig.RequiredForOnline = "no";
  };

  # services.opentelemetry-collector = {
  #   enable = true;
  #   configFile = pkgs.writeText "otel-collector-config.yaml" ''
  #     receivers:
  #       otlp:
  #         protocols:
  #           grpc:
  #             endpoint: 127.0.0.1:4317
  #           http:
  #             endpoint: 127.0.0.1:4318

  #     processors:
  #       batch:

  #     exporters:
  #       debug:
  #         verbosity: detailed
  #       prometheus:
  #         endpoint: 0.0.0.0:8889
  #         resource_to_telemetry_conversion:
  #           enabled: true

  #     service:
  #       pipelines:
  #         traces:
  #           receivers: [otlp]
  #           processors: [batch]
  #           exporters: [debug]
  #         metrics:
  #           receivers: [otlp]
  #           processors: [batch]
  #           exporters: [debug, prometheus]
  #         logs:
  #           receivers: [otlp]
  #           processors: [batch]
  #           exporters: [debug]
  #   '';
  #   package = pkgs.opentelemetry-collector-contrib;
  # };

  # IndieAuth client metadata for Claude Code MCP - served on localhost for HA to fetch
  services.nginx.virtualHosts."localhost-oauth" = {
    listen = [
      {
        addr = "127.0.0.1";
        port = 80;
      }
    ];
    locations."= /oauth/client" = {
      extraConfig = ''
        default_type text/html;
        return 200 '<!DOCTYPE html><html><head><link rel="redirect_uri" href="http://127.0.0.1/"><link rel="redirect_uri" href="http://localhost/"><link rel="redirect_uri" href="http://127.0.0.1/callback"><link rel="redirect_uri" href="http://localhost/callback"></head><body><h1>Claude Code MCP Client</h1></body></html>';
      '';
    };
    locations."/" = {
      return = "404";
    };
  };

  services = {
    iperf3 = {
      enable = true;
      # LAN-only (profiles/router/linux.nix allows 5201 on the LAN bridge);
      # openFirewall would expose it on the WAN interface too.
      openFirewall = false;
    };
  };

  # Enable switchdev mode on ConnectX-4 WAN port for hardware TC offload.
  # Run this in initrd, before stage 2: the eswitch is a NIC-wide resource on
  # ConnectX-4, so toggling it on PF0 (WAN) briefly drops the link on PF1 (LAN)
  # as well. Doing it in initrd means nothing in userspace cares about the
  # carrier yet — no bridge, no networkd — so the flap is invisible by the
  # time stage 2 starts. Wait on the PCI device unit, not the netdev name,
  # because switchdev destroys and recreates the netdev.
  boot.initrd.systemd.services.mlx5-switchdev-wan = lib.mkIf config.router.legacyPcieNetwork.enable {
    description = "Enable switchdev mode on ConnectX-4 Lx WAN port";
    wantedBy = [ "initrd.target" ];
    before = [ "initrd-switch-root.target" ];
    # Depend on the netdev unit, not the PCI device unit: PCI device units
    # aren't tagged by udev in initrd and never activate, causing a 90s
    # default-timeout wait. The netdev (after udev .link rename) is reliable.
    after = [ "sys-subsystem-net-devices-enp1s0f0np0.device" ];
    wants = [ "sys-subsystem-net-devices-enp1s0f0np0.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iproute2}/bin/devlink dev eswitch set pci/0000:01:00.0 mode switchdev";
    };
  };
  # devlink is in iproute2 — pull it into the initrd image.
  boot.initrd.systemd.storePaths = lib.mkIf config.router.legacyPcieNetwork.enable [ "${pkgs.iproute2}/bin/devlink" ];

  # Configure 25G interfaces (ConnectX-4) - requires manual speed/FEC settings
  systemd.services.ethtool-enp1s0f0np0 = lib.mkIf config.router.legacyPcieNetwork.enable {
    description = "Configure enp1s0f0np0 25G WAN link settings";
    after = [ "sys-subsystem-net-devices-enp1s0f0np0.device" ];
    wants = [ "sys-subsystem-net-devices-enp1s0f0np0.device" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "${pkgs.ethtool}/bin/ethtool -s enp1s0f0np0 speed 25000 autoneg off"
        "${pkgs.ethtool}/bin/ethtool --set-fec enp1s0f0np0 encoding rs"
      ];
    };
  };

  # Realtek 10G tuning: GRO forwarding + RPS across all CPUs. The NIC is
  # renamed to lan10g by MAC (profiles/router/linux.nix) because its kernel
  # name flaps (enp2s0/enp7s0) when it drops off the PCIe bus across boots.
  systemd.services.ethtool-lan10g = lib.mkIf config.router.legacyPcieNetwork.enable {
    description = "Configure lan10g Realtek 10G offload and RPS";
    after = [ "sys-subsystem-net-devices-lan10g.device" ];
    wants = [ "sys-subsystem-net-devices-lan10g.device" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.ethtool ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ethtool -K lan10g rx-udp-gro-forwarding on
      for q in /sys/class/net/lan10g/queues/rx-*/rps_cpus; do
        echo ffff > "$q"
      done
    '';
  };

  # Safety net for the same PCIe/rename flakiness. On the 2026-08-10 boot the
  # kernel name flapped (lan10g -> eth1 -> lan10g) while systemd-networkd was
  # enumerating; networkd then marked the link *unmanaged* for the rest of the
  # boot, so 20-lan-10g-realtek.network never applied. The port stayed down and
  # unenslaved, which silently cut off everything behind the 10G switch — the
  # PoE switch, the Zigbee coordinator, and every Zigbee light with it. Neither
  # `networkctl reconfigure` nor a udev re-add persuades networkd to adopt the
  # link once it has done this; only a full networkd restart does, which is not
  # something to do unattended on the router.
  #
  # So reconcile the end state directly: idempotent, and a no-op on every boot
  # where networkd behaved.
  systemd.services.lan10g-bridge-reconcile = lib.mkIf config.router.legacyPcieNetwork.enable {
    description = "Enslave lan10g to the LAN bridge if networkd left it unmanaged";
    after = [ "systemd-networkd.service" "sys-subsystem-net-devices-lan10g.device" ];
    wants = [ "sys-subsystem-net-devices-lan10g.device" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iproute2 ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [ ! -e /sys/class/net/lan10g ]; then
        echo "lan10g absent (NIC missing from the PCIe bus this boot); nothing to do"
        exit 0
      fi
      master=$(sed -n 's/^INTERFACE=//p' /sys/class/net/lan10g/master/uevent 2>/dev/null || true)
      if [ "$master" = "${network.ports.router.lanBridge}" ]; then
        echo "lan10g already enslaved to ${network.ports.router.lanBridge}; nothing to do"
        exit 0
      fi
      echo "lan10g not enslaved (master=$master); reconciling"
      ip link set lan10g mtu ${toString network.vlans.lan.mtu}
      ip link set lan10g up
      ip link set lan10g master ${network.ports.router.lanBridge}
    '';
  };

  networking.hosts = {
    "127.0.0.1" = [
      "localhost"
      network.domains.public
      "router.${network.domains.public}"
      "frigate.${network.domains.public}"
    ];
    ${network.primaryIp network.hosts.trex} = [ "trex.${network.domains.public}" ];
  };

  # Only `mlx5_core` actually needs to be in initrd — the switchdev devlink
  # call depends on it. Everything else is fine to load in stage 2: the
  # smaller initrd udev queue means systemd-udevd drains faster on
  # initrd→stage-2 transition (saves ~20s of boot).
  boot.initrd.kernelModules = lib.mkIf config.router.legacyPcieNetwork.enable [
    "mlx5_core"
  ];

  boot.kernelModules = [
    "nf_tables"
    "nft_compat"
    "igc"
    "ixgbe"
    "it87"
    "vfio"
  ];

  # The board's IT8613E is compatible with the IT8620E register layout but is
  # not detected by the in-tree driver. This exact mapping was verified on the
  # router: this exposes the board's fan tachometers and PWM outputs.
  #
  # snd_hda_intel: the index/id arrays are indexed by probe order, which for
  # two functions of the same PCI device is ascending function number —
  # c9:00.1 (GPU HDMI) then c9:00.6 (ALC269VC). Naming them makes the
  # spotifyd device string above stable regardless of what the ids would
  # otherwise auto-suffix to ("Generic"/"Generic_1").
  boot.extraModprobeConfig = ''
    options it87 force_id=0x8620
    options snd_hda_intel index=0,1 id=hdmi,analog
  '';

  systemd.services.router-fans-full-speed = {
    description = "Run the router system fans at full PWM duty";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      controller=
      for candidate in /sys/class/hwmon/hwmon*; do
        if [ "$(${pkgs.coreutils}/bin/cat "$candidate/name" 2>/dev/null || true)" = it8620 ]; then
          controller="$candidate"
          break
        fi
      done

      if [ -z "$controller" ]; then
        echo "IT8620 fan controller not found" >&2
        exit 1
      fi

      found=false
      for pwm in "$controller"/pwm*; do
        name="''${pwm##*/}"
        case "$name" in
          pwm[0-9]|pwm[0-9][0-9]) ;;
          *) continue ;;
        esac

        # pwm*_enable=1 selects manual control; 255 is 100% duty.
        enable="''${pwm}_enable"
        if [ -e "$enable" ]; then
          if ! printf '1\n' > "$enable" 2>/dev/null; then
            echo "$name is firmware-locked; leaving it unchanged"
            continue
          fi
          selected="$(${pkgs.coreutils}/bin/cat "$enable")"
          if [ "$selected" != 1 ]; then
            echo "$name remains in mode $selected; leaving it unchanged"
            continue
          fi
        fi
        if ! printf '255\n' > "$pwm" 2>/dev/null; then
          echo "$name rejects manual duty control; leaving it unchanged"
          continue
        fi

        actual="$(${pkgs.coreutils}/bin/cat "$pwm")"
        if [ "$actual" != 255 ]; then
          echo "$name readback is $actual, expected 255" >&2
          exit 1
        fi
        found=true
      done

      if ! $found; then
        echo "IT8620 exposes no PWM outputs" >&2
        exit 1
      fi
    '';
  };

  fileSystems."/" = {
    device = "zpool/root/nixos-router";
    fsType = "zfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/5826-D605";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  networking = {
    hostName = "router";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
  };
}
