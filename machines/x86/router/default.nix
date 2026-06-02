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

  # Mac-RDMA bench test: allow uc_oneway / uc_write_verify metadata
  # sockets on thunderbolt0 (point-to-point to mbp).
  networking.firewall.interfaces."thunderbolt0".allowedTCPPortRanges = [
    { from = 18000; to = 19999; }
    { from = 29000; to = 29999; }
  ];

  # Mac-RDMA test mode: keep stock thunderbolt-net loaded (for the TBnet IP
  # carrier that stock_proxy proxies the GID against) but DO NOT bridge
  # thunderbolt0 into br0.lan. The 50-thunderbolt link match still uses
  # IPv4LL+mDNS as a baseline; the 20-thunderbolt0 override below pins the
  # mac-facing IP at 10.0.3.2/24, matching the 2026-05-17 e14 known-good
  # router-VM/MBP topology.
  profiles.thunderbolt-bridge.bridgeThunderboltNet = false;

  # Override testing kernel from radeon.nix - router doesn't need HDMI VRR patches
  # and ZFS doesn't support 6.19-rc yet
  # boot.kernelPackages = lib.mkForce pkgs.linuxKernel.packages.linux_6_18;
  # boot.kernelPatches = lib.mkForce [];

  # Realtek RTL8127 10GbE out-of-tree driver with RSS/multi-queue support
  # The in-kernel r8169 driver only has single-queue support for this chip
  boot.extraModulePackages = [
    (config.boot.kernelPackages.callPackage ../../../packages/r8127 { })
  ];
  boot.blacklistedKernelModules = [ "r8169" ];

  boot.kernelParams = [
    "video=HDMI-A-1:1920x1080@60e" # 'e' forces enable even without EDID
    "iommu=pt"
  ];

  deployment.targetHost = network.domains.public;
  # deployment.targetHost = "10.86.167.2";
  #  deployment.targetHost = network.routerIp;

  # deployment.targetHost = "router.${network.domains.public}";
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
    ../../../profiles/amd-npu.nix
    ../../../profiles/router/linux.nix
    ../../../profiles/router/services.nix
    # ../../../profiles/router/ap.nix  # WiFi card not installed
    ../../../profiles/router/wireguard.nix
    ../../../profiles/thunderbolt-bridge.nix
    # Keep router on the stock nixpkgs kernel while the custom USB4/RDMA
    # patchset is not applying cleanly to the current kernel.
    # ../../../profiles/thunderbolt-ibverbs-kernel-stable.nix
    # ../../../profiles/thunderbolt-ibverbs-mac-host.nix

    ../../../services/buildfarm-slave.nix
    ../../../containers/unifi.nix
    ../../../services/p2pool.nix
    ../../../services/p2pool-exporter.nix
    ../../../services/home-assistant/default.nix
    ../../../services/frigate.nix
  ];

  hardware.cpu.amd.ryzen-smu.enable = true;
  programs.ryzen-monitor-ng.enable = true;
  environment.systemPackages = with pkgs; [
    ryzenadj
    mstflint
  ];

  # services.ryzenadj = {
  #   enable = true;
  #   # stapmLimit = 30000;
  #   fastLimit = 45000;
  #   slowLimit = 38000;
  #   tctlTemp = 90;
  # };

  systemd.network.networks."20-nanokvm" = {
    matchConfig.Driver = "rndis_host";
    address = [
      "10.86.167.2/24"
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

  # Mac-RDMA test bench: thunderbolt0 standalone at 10.0.3.2/24, paired with
  # the MBP whose en3 we pin to 10.0.3.3/24. ardma0 is a dummy interface that
  # carries the IPv4-mapped RDMA GID (10.0.3.44/32) — stable across cable
  # replugs and independent of the TBnet IP carrier MAC. The thunderbolt_ibverbs
  # module is configured below with roce_netdev=ardma0 + tbnet_identity_gid=
  # ardma0, mirroring the 2026-05-17 e14 known-good setup.
  systemd.network.netdevs."30-ardma0" = {
    netdevConfig = {
      Kind = "dummy";
      Name = "ardma0";
    };
  };
  systemd.network.networks."20-thunderbolt0-rdma-test" = {
    matchConfig.Name = "thunderbolt0";
    address = [ "10.0.3.2/24" ];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = "no";
      ConfigureWithoutCarrier = true;
    };
    linkConfig = {
      MTUBytes = "9000";
      RequiredForOnline = "no";
    };
  };
  systemd.network.networks."30-ardma0" = {
    matchConfig.Name = "ardma0";
    address = [ "10.0.3.44/32" ];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = "no";
      ConfigureWithoutCarrier = true;
    };
    linkConfig.RequiredForOnline = "no";
  };

  hardware."thunderbolt-ibverbs" = {
    enable = true;
    config = {
      profile = "mac_compat";
      compat = "auto";
      tbnet = "allow";
      tbnet_identity = "stock_proxy";
      tbnet_identity_tbnet = "thunderbolt0";
      tbnet_identity_gid = "ardma0";
      roce_netdev = "ardma0";
      lanes = "1";
      bind_services = true;
      allocate_rings = true;
      start_rings = true;
      enable_tunnels = true;
      native_data = false;
      apple_data = true;
      register_verbs = true;
      apple_tx_max_inflight_wr = "1";
      apple_tx_max_inflight_frames = "2";
      apple_rx_pending_bytes = "16777216";
      apple_rx_pending_slots = "4096";
      apple_rx_pending_total_bytes = "67108864";
    };
    check = {
      afterReload = true;
      requireVerbs = true;
      expectedNativeControl = null;
    };
  };

  services.redis.servers.p2pool = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
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

  # Enable switchdev mode on ConnectX-4 WAN port for hardware TC offload
  # Must run before networkd configures the interface
  # Note: Port 1 (LAN) stays in legacy mode - switchdev is incompatible with Linux bridge
  # Wait on PCI device, not interface name — switchdev destroys/recreates the netdev
  systemd.services.mlx5-switchdev-wan = {
    description = "Enable switchdev mode on ConnectX-4 Lx WAN port";
    before = [ "systemd-networkd.service" "network-pre.target" ];
    after = [ "systemd-udevd.service" "sys-devices-pci0000:00-0000:00:01.1-0000:01:00.0.device" ];
    wants = [ "sys-devices-pci0000:00-0000:00:01.1-0000:01:00.0.device" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iproute2}/bin/devlink dev eswitch set pci/0000:01:00.0 mode switchdev";
    };
  };

  # Configure 25G interfaces (ConnectX-4) - requires manual speed/FEC settings
  systemd.services.ethtool-enp1s0f0np0 = {
    description = "Configure enp1s0f0np0 25G WAN link settings";
    after = [ "sys-subsystem-net-devices-enp1s0f0np0.device" "mlx5-switchdev-wan.service" ];
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

  # Realtek 10G tuning: GRO forwarding + RPS across all CPUs
  systemd.services.ethtool-enp2s0 = {
    description = "Configure enp2s0 Realtek 10G offload and RPS";
    after = [ "sys-subsystem-net-devices-enp2s0.device" ];
    wants = [ "sys-subsystem-net-devices-enp2s0.device" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.ethtool ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ethtool -K enp2s0 rx-udp-gro-forwarding on
      for q in /sys/class/net/enp2s0/queues/rx-*/rps_cpus; do
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

  boot.initrd.kernelModules = [
    "nf_tables"
    "nft_compat"
    "igc"
    "ixgbe"
    "vfio"
    "mlx5_core"
  ];

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
