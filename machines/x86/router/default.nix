{ inputs
, config
, lib
, pkgs
, network
, ...
}: {
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
    address = network.routerIp;
  };
  networking.firewall.interfaces."br0.lan".allowedTCPPorts = [ 6052 ];

  # Pin the router to the explicit RC package set instead of following
  # nixpkgs' moving linuxPackages_latest from profiles/uefi-boot.nix.
  boot.kernelPackages = lib.mkForce pkgs.linuxKernel.packages.linux_7_2_rc2;

  # Realtek RTL8127 10GbE out-of-tree driver with RSS/multi-queue support
  # The in-kernel r8169 driver only has single-queue support for this chip
  boot.extraModulePackages = [
    (config.boot.kernelPackages.callPackage ../../../packages/r8127 { })
  ];
  boot.blacklistedKernelModules = [ "r8169" ];

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
    ../../../services/frigate.nix
  ];

  hardware.cpu.amd.ryzen-smu.enable = true;
  programs.ryzen-monitor-ng.enable = true;

  # Declaratively authorize the IOCREST USB4 10GbE enclosure (atlantic,
  # br0.lan port). Domain security is "user" and boltd's authorization store
  # (/var/lib/boltd) doesn't survive impermanence, so without this the NIC
  # stays unauthorized after every boot/re-plug and its LAN segment goes dark.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{unique_id}=="c8010000-00b1-bd08-2230-ad1cc6200123", ATTR{authorized}=="0", ATTR{authorized}="1"
  '';

  environment.systemPackages = with pkgs; [
    ryzenadj
    mstflint
    rdma-core
    perftest
    uhubctl
  ];

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
      openFirewall = true;
    };
  };

  # Enable switchdev mode on ConnectX-4 WAN port for hardware TC offload.
  # Run this in initrd, before stage 2: the eswitch is a NIC-wide resource on
  # ConnectX-4, so toggling it on PF0 (WAN) briefly drops the link on PF1 (LAN)
  # as well. Doing it in initrd means nothing in userspace cares about the
  # carrier yet — no bridge, no networkd — so the flap is invisible by the
  # time stage 2 starts. Wait on the PCI device unit, not the netdev name,
  # because switchdev destroys and recreates the netdev.
  boot.initrd.systemd.services.mlx5-switchdev-wan = {
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
  boot.initrd.systemd.storePaths = [ "${pkgs.iproute2}/bin/devlink" ];

  # Configure 25G interfaces (ConnectX-4) - requires manual speed/FEC settings
  systemd.services.ethtool-enp1s0f0np0 = {
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
  systemd.services.ethtool-lan10g = {
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
  boot.initrd.kernelModules = [
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
  # router: fan2_input tracks the system fan, and pwm2 controls it.
  boot.extraModprobeConfig = ''
    options it87 force_id=0x8620
  '';

  systemd.services.router-system-fan-max = {
    description = "Set the verified router system fan to maximum speed";
    after = [ "systemd-modules-load.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu

      for hwmon in /sys/class/hwmon/hwmon*; do
        [ -r "$hwmon/name" ] || continue
        [ "$(cat "$hwmon/name")" = "it8620" ] || continue
        [ -r "$hwmon/fan2_input" ] || continue
        [ -w "$hwmon/pwm2_enable" ] || continue
        [ -w "$hwmon/pwm2" ] || continue

        echo 1 > "$hwmon/pwm2_enable"
        echo 255 > "$hwmon/pwm2"
        exit 0
      done

      echo "verified IT8620 hwmon fan2/pwm2 mapping was not found" >&2
      exit 1
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
