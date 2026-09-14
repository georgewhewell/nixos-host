{ pkgs
, lib
, inputs
, config
, mkSecret
, network
, ...
}:
let
  self = network.hosts.fuckup;
in
{
  /*
    AMD Ryzen 9 9950X3D
  */
  sconfig = {
    profile = "desktop";
    home-manager = {
      enable = true;
      enableDevelopment = true;
      enableGraphical = true;
      enableCad = true;
    };
    xmrig = with pkgs; {
      enable = true;
      package = xmrig-zen5;
      cudaPlugin = null;
      httpApi.enable = true;
      httpApi.accessToken = "xmrig";
      inhibit.dota2.enable = true;
    };
  };

  system.stateVersion = "25.05";

  # Personal Codex quota is read from this host's live credential. Keeping
  # the exporter beside the token avoids cloning a rotating OAuth credential.
  services.llm-quota-exporter = {
    enable = true;
    providers = "openai";
  };

  deployment.targetHost = network.primaryIp self;
  deployment.targetUser = "grw";

  sops.secrets.mosquitto-password = mkSecret "mosquitto-password" {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  boot.tmp.useTmpfs = lib.mkForce false;

  hardware.enableAllHardware = true;
  nix.settings.system-features = [ "gccarch-znver5" "rtx4090" "9950x3d" ];

  programs.gpu-screen-recorder.enable = true;

  # Shared read-only model cache served by trex instead of a local HF cache.
  # Strix nodes do not use this NFS path; they mount the pinned NVMe/RDMA
  # snapshot directly.
  fileSystems."/models" = {
    device = "${network.primaryIp network.hosts.trex}:/strix-models";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "ro"
      "nofail"
      "_netdev"
      "x-systemd.automount"
      "rsize=1048576"
      "wsize=1048576"
      "nconnect=8"
    ];
  };
  boot.supportedFilesystems = [ "nfs" ];

  # Point HuggingFace tooling at the shared snapshot and stay offline w.r.t.
  # the Hub — model acquisition belongs to trex (mirrors the strix nodes).
  environment.variables = {
    HF_HOME = "/models/.cache/huggingface";
    HF_HUB_OFFLINE = "1";
    TRANSFORMERS_OFFLINE = "1";
    HF_HUB_DISABLE_TELEMETRY = "1";
  };

  environment.systemPackages = [
    pkgs.kexec-tools
    pkgs.gpu-screen-recorder-gtk
    pkgs.wl-screenrec
    (pkgs.writeShellScriptBin "wl-capture" ''
      set -euo pipefail

      output="''${WL_CAPTURE_OUTPUT:-DP-3}"
      fps="''${WL_CAPTURE_FPS:-60}"
      codec="''${WL_CAPTURE_CODEC:-h264}"
      dir="''${WL_CAPTURE_DIR:-$HOME/Videos/Screencasts}"
      mkdir -p "$dir"

      file="$dir/wl-capture-$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S).mp4"
      export PATH="/run/wrappers/bin:$PATH"
      exec ${pkgs.gpu-screen-recorder}/bin/gpu-screen-recorder \
        -w "$output" \
        -f "$fps" \
        -k "$codec" \
        -encoder gpu \
        -q high \
        -cursor yes \
        -o "$file"
    '')
  ];

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd
    common-gpu-amd
    inputs.disko.nixosModules.disko

    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/nas-mounts.nix
    # ../../../profiles/radeon.nix
    ../../../profiles/nvidia.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/zfs.nix
    ../../../profiles/development.nix
    ../../../profiles/graphical.nix
    ../../../profiles/displaylink.nix
    ../../../profiles/wayland-compositors-test.nix

    ../../../profiles/thunderbolt-ibverbs-kernel-stable.nix
    ../../../profiles/thunderbolt-bridge.nix

    ../../../services/buildfarm-slave.nix
    ../../../services/hydra-builder-slave.nix

    inputs.nix-strix-halo.nixosModules.default
    inputs.nix-strix-halo.nixosModules.benchmark-runner
    # inputs.nix-strix-halo.nixosModules.tuning

    ./fabric-rdma-vf.nix
    ./nvme-models.nix
    ./claw-usb-live.nix
  ];

  # Enabling any benchmark runner makes nix-strix-halo's benchmark-runner
  # module bind `benchmark.modelsPath` (default "/models") into
  # nix.settings.extra-sandbox-paths unconditionally, for every build this
  # daemon runs -- not just benchmark derivations. On fuckup, "/models" is
  # the NFS mount above, an x-systemd.automount unit: it is absent until
  # something first touches it, and the sandbox's bind-mount cannot wait for
  # that automount to fire, so it fails outright until a later build
  # retriggers it. The cuda-rtx4090 runner below never references files
  # under /models, so point the module at a plain local directory instead of
  # the autofs mount, which sidesteps the race without touching the real
  # /models mount used for interactive/HF-Hub access.
  benchmark.modelsPath = "/var/lib/benchmark-models-stub";

  # nix-strix-halo's benchmark-runner module already creates
  # `benchmark.modelsPath` via its own tmpfiles rule, so this is currently
  # redundant -- but that rule is an implementation detail of a separately
  # pinned, external module, and if the stub directory did not exist the
  # sandbox bind would fail again (with "does not exist" instead of
  # "Operation not permitted"), since modelsPath is spliced into
  # extra-sandbox-paths without the optional `?` suffix. Declare it here too
  # so the invariant holds regardless of upstream's internals.
  systemd.tmpfiles.rules = [ "d /var/lib/benchmark-models-stub 0755 root root -" ];

  benchmark.runners.cuda-rtx4090 = {
    requireIommuOff = false;
    gpus = [
      {
        type = "nvidia";
        arch = "rtx4090";
      }
    ];
    systemFeatures = [
      "benchmark"
      "cuda"
      "nvidia"
    ];
    extraSandboxPaths = [
      "/proc/driver/nvidia"
      "/run/opengl-driver"
      "/run/opengl-driver-lib=/run/opengl-driver/lib"
      "${config.hardware.nvidia.package}"
    ];
  };

  home-manager.users.grw =
    { config
    , lib
    , pkgs
    , ...
    }: {
      home.activation.kwinGameInput = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
          --file "$HOME/.config/kwinrc" \
          --group MouseBindings \
          --key CommandAllKey Meta
      '';

      # baloo_file_extractor (kde-baloo.service) ran for 3.5 days straight
      # pegging a core and peaking at 25G RSS while indexing. Turn indexing
      # off and mask the service so it can't restart itself.
      home.activation.baloofileDisable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
          --file "$HOME/.config/baloofilerc" \
          --group "Basic Settings" \
          --key Indexing-Enabled false
      '';

      xdg.configFile."systemd/user/kde-baloo.service".source =
        config.lib.file.mkOutOfStoreSymlink "/dev/null";

      systemd.user.services.qwen38-dense-tunnel = {
        Unit = {
          Description = "SSH tunnel to the Qwen3.8-27B vLLM Metal server on mbp";
          After = [ "network-online.target" ];
        };
        Service = {
          ExecStart = "${pkgs.openssh}/bin/ssh -N -o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new -L 127.0.0.1:18150:127.0.0.1:11500 grw@${network.primaryIp network.hosts.mbp}";
          Restart = "always";
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };

  networking.firewall.allowedTCPPorts = [ 8080 8081 ];

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = lib.mkForce true;
    };
  };

  # ZFS snapshot management - long retention for backup archive
  services.sanoid = {
    enable = true;
    interval = "hourly";
    datasets."archive/pool3d" = {
      recursive = true;
      autosnap = false; # Don't create snapshots, just prune received ones
      hourly = 48;
      daily = 90;
      weekly = 52;
      monthly = 24;
    };
  };

  # Allow trex syncoid user to SSH in for replication
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB5dlmnSV46Mvtz5f+yVh23RnUPUw/T6Kcmx0LkODx5C syncoid@trex"
  ];

  # Import the archive pool at boot
  boot.zfs.extraPools = [ "archive" ];

  disko.devices = {
    disk = {
      nvme = {
        device = "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "500M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
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

  hardware.mediatek-mt7927.enable = true;

  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom="CH"
    options sp5100_tco heartbeat=30 nowayout=1 action=0
  '';

  boot.kernelModules = [ "sp5100_tco" ];




  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = lib.mkForce true;
  };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "performance";
  };

  profiles.thunderbolt-bridge = {
    enableThunderboltNet = false;
    bridgeThunderboltNet = false;
  };

  hardware.thunderbolt-ibverbs = {
    enable = true;
    loadOnBoot = false;
    blacklist.enable = true;
    config = {
      profile = "linux_perf";
      compat = "off";
      tbnet = "prefer_rdma";
      tbnet_identity = "off";
      lanes = "2";
      bind_services = true;
      allocate_rings = true;
      start_rings = true;
      negotiate_native = true;
      enable_tunnels = true;
      native_control_trace = true;
      native_ready_timeout_optimistic = true;
      register_verbs = true;
      roce_netdev = "br0.lan";
    };
  };

  networking = {
    hostName = "fuckup";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    useDHCP = false;
    firewall.enable = false;
    # Let NetworkManager own only WiFi; systemd-networkd keeps the
    # wired bridge it already configures below.
    networkmanager = {
      enable = true;
      settings.keyfile.unmanaged-devices = "*,except:type:wifi";
    };
  };

  systemd.network =
    let
      lanBridge = "br0.lan";
    in
    {
      enable = true;
      wait-online = {
        enable = true;
        anyInterface = true;
      };
      # The fabric PF's .link profile (rename + 10G thermal cap) lives in
      # fabric-rdma-vf.nix as 10-cx4-fabric, matched by permanent MAC. Do not
      # add another .link for that port here: udev applies only the first
      # matching profile.
      netdevs = {
        "20-${lanBridge}" = {
          netdevConfig = {
            Kind = "bridge";
            Name = lanBridge;
          };
          bridgeConfig.STP = true;
        };
      };
      networks = {
        "10-bridge" = {
          matchConfig.Name = lanBridge;
          networkConfig.IPv6AcceptRA = true;
          address = [
            (network.cidrOf "lan" self.addresses.lan)
            # Control-plane rescue subnet; see network.nix `vlans.rescue`.
            (network.cidrOf "rescue" self.addresses.rescue)
          ];
          gateway = [ network.routerIp ];
          dns = [ network.dnsIp ];
        };
        "10-mlx5" = {
          # Match the PF by permanent MAC ONLY -- never add Driver= here.
          # networkd resolves Driver= with a single ethtool call keyed on the
          # ifname it holds at that instant and never retries it. Because
          # systemd-networkd.socket (ListenNetlink=route) buffers every link
          # event since early boot, networkd replays the kernel's original
          # "eth1" add event after the 10-cx4-fabric rename has already
          # happened, makes that one ethtool call as "eth1", gets ENODEV, and
          # leaves the driver unknown for the rest of the boot -- so a match
          # containing Driver= can never succeed and the port stays unmanaged.
          # PermanentMACAddress= is read from the IFLA_PERM_ADDRESS attribute
          # carried by every netlink message, independent of the name.
          matchConfig.PermanentMACAddress = self.mac;
          networkConfig = {
            Bridge = lanBridge;
            ConfigureWithoutCarrier = true;
          };
          # Jumbo on the ConnectX PFs so the RoCE VF in fabric-rdma-vf.nix can
          # reach MTU 9000 -- a VF's MTU is capped by its PF's. This does not
          # also give br0.lan jumbo on its own: a Linux bridge takes the
          # minimum MTU of its ports, so every other member has to be raised
          # too -- see the igc and Aquantia blocks below.
          linkConfig.MTUBytes = "9000";
          linkConfig.RequiredForOnline = "enslaved";
        };
        "10-igc" = {
          matchConfig.Driver = "igc";
          networkConfig = {
            Bridge = lanBridge;
            ConfigureWithoutCarrier = true;
          };
          linkConfig = {
            MTUBytes = "9000";
            RequiredForOnline = "enslaved";
          };
        };
        # enp10s0 has the long cable to the 400G switch management port,
        # which lands in the cluster MANAGEMENT LAN (23.x), not the fabric
        # (25.x). It must stay out of br0.lan (bridging it loops the LAN via
        # the mgmt switch) and carries no address: fuckup has no dataplane
        # attachment to the 192.168.25.0/24 fabric without an SFP+ RJ45
        # transceiver or DAC between the CX5 and the 400G switch.
        "10-fabric" = {
          matchConfig.Name = "enp10s0";
          networkConfig.ConfigureWithoutCarrier = true;
          linkConfig.RequiredForOnline = false;
          linkConfig.ActivationPolicy = "down";
        };
        # Keep the second Aquantia port on the LAN bridge as before, but at
        # the same 9000 MTU as the ConnectX PFs. It is only a 2.5G fallback
        # and has had no carrier since 2026-07-15, yet because a Linux bridge
        # takes the minimum MTU of its ports, leaving it at 1500 silently
        # pinned br0.lan -- and so every LAN flow, including the 25G path --
        # to 1500 while the router and trex both ran 9000.
        "11-aquantia-lan" = {
          matchConfig.Name = "enp11s0";
          networkConfig = {
            Bridge = lanBridge;
            ConfigureWithoutCarrier = true;
          };
          linkConfig = {
            MTUBytes = "9000";
            RequiredForOnline = false;
          };
        };
      };
    };
}
