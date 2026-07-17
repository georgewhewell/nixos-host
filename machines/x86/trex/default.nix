{ pkgs
, lib
, inputs
, mkSecret
, config
, network
, ...
}:
let
  self = network.hosts.trex;

  # ConnectX-4 switchdev: pin interface names to the ASIC's phys_switch_id so
  # they survive PCIe re-enumeration. The card's bus number moves whenever the
  # PCIe tree is re-walked (e.g. toggling the BMC's shared-NIC mode), and with
  # `pci=realloc=off` the kernel-assigned enpXsY names move with it. Anchoring
  # on the switch id (stable, ASIC-derived) instead of the bus keeps OVS,
  # sriov-init and networkd matching the right device every boot.
  mlxSwitchId = "86240d00034b6b50";
  mlxPfMac = "50:6b:4b:0d:24:86";
  mlxPfName = "mlxlan0";
  # VF7 currently enumerates as 0000:aa:01.0 and times out in mlx5_core
  # ENABLE_HCA, adding about a minute to initrd. Use the seven working VFs.
  mlxVfCount = 7;
  # Representor names, index-aligned with phys_port_name pf0vf0..pf0vf{N-1}.
  mlxRepNames = lib.genList (i: "${mlxPfName}r${toString i}") mlxVfCount;
  # i40e ports also move when the PCIe tree is re-walked. Keep OVS pointed at
  # MAC-pinned names instead of enpXsY names.
  i40ePorts = {
    i40e0 = "9c:6b:00:57:30:60";
    i40e1 = "9c:6b:00:57:30:61";
  };
  i40eNames = builtins.attrNames i40ePorts;
  mlxVfName = pkgs.writeShellScript "mlx-vf-name" ''
    set -eu

    devpath="/sys/$1"
    vf_device="$(${pkgs.coreutils}/bin/readlink -f "$devpath/device")"
    physfn="$vf_device/physfn"

    [ -e "$physfn/net/${mlxPfName}" ] || exit 1

    for virtfn in "$physfn"/virtfn*; do
      [ -e "$virtfn" ] || continue
      if [ "$(${pkgs.coreutils}/bin/readlink -f "$virtfn")" = "$vf_device" ]; then
        idx="''${virtfn##*virtfn}"
        case "$idx" in
          ""|*[!0-9]*) exit 1 ;;
        esac
        [ "$idx" -lt ${toString mlxVfCount} ] || exit 1
        printf '%s\n' "${mlxPfName}v$idx"
        exit 0
      fi
    done

    exit 1
  '';
  mlxUdevRules = pkgs.writeTextFile {
    name = "75-mlx-switchdev-names";
    destination = "/etc/udev/rules.d/75-mlx-switchdev-names.rules";
    text = ''
      SUBSYSTEM=="net", ACTION=="add", ATTR{phys_switch_id}=="${mlxSwitchId}", ATTR{phys_port_name}=="p0", NAME="${mlxPfName}"
      SUBSYSTEM=="net", ACTION=="add", DRIVERS=="mlx5_core", ATTRS{vendor}=="0x15b3", ATTRS{device}=="0x1014", PROGRAM="${mlxVfName} %p", NAME="%c"
    '' + lib.concatStrings (lib.genList
      (i: ''
        SUBSYSTEM=="net", ACTION=="add", ATTR{phys_switch_id}=="${mlxSwitchId}", ATTR{phys_port_name}=="pf0vf${toString i}", NAME="${mlxPfName}r${toString i}"
      '')
      mlxVfCount);
  };
in
{
  /*
    trex: trx90 system

    # fans:
    # CPU_FAN1: AIO Radiator fans
    # CPU_FAN2/WP: Pump
    # CHA_FAN1/WP: 140mm intakes
    # CHA_FAN2/WP: Unsure.. VRAM?
    # CHA_FAN3/WP: Unsure.. exhaust?
    # MOS_FAN1/MOS_FAN2: VRM
  */
  sconfig = {
    profile = "desktop";
    home-manager = {
      enable = true;
      enableVscodeServer = true;
    };
    xmrig = {
      enable = true;
      package = pkgs.xmrig-zen4;
      uclampMax = 95;
    };
    gcp-ddns = {
      enable = true;
      hostName = true;
    };
    netconsole.collector = {
      enable = true;
      port = 6666;
      logFile = "/var/log/netconsole/strix.log";
      openFirewall = true;
    };
  };

  systemd.timers.gcp-ddns.timerConfig.OnActiveSec = lib.mkForce "15min";
  systemd.services.gcp-ddns.serviceConfig.TimeoutStartSec = "15min";

  # 7985WX - big parallel builder
  nix.settings = {
    system-features = [ "gccarch-znver4" "kvm" "big-parallel" "nixos-test" ];
    download-buffer-size = 104857600; # 100 MiB
    http-connections = 64;
    # Sign locally-built store paths with our cache key so `nix copy` to
    # strix-1/strix-2 (which trust this key via modules/nix.nix) is
    # accepted without --no-check-sigs.
    secret-key-files = [ config.sops.secrets.nix-cache-key.path ];
  };

  # The Strix clients are netbooted with a read-only /nix/store, so they cannot
  # act as writable Nix builders for trex. Keep the other remote builders (in
  # particular the AArch64 and Darwin machines) available.
  benchmark.executor.builders."strix-1".enable = lib.mkForce false;
  benchmark.executor.builders."strix-2".enable = lib.mkForce false;

  boot.kernel.sysctl = {
    # Network buffer defaults
    "net.core.rmem_default" = 1048576;
    "net.core.wmem_default" = 1048576;
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.core.netdev_max_backlog" = 50000;
    "net.core.netdev_budget" = 1000;
    "net.core.somaxconn" = 8192;

    # TCP tuning for 25Gbps
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.ipv4.tcp_rmem" = "4096 1048576 134217728";
    "net.ipv4.tcp_wmem" = "4096 1048576 134217728";
    "net.ipv4.tcp_slow_start_after_idle" = 0;
    "net.ipv4.tcp_mtu_probing" = 1;
    "net.ipv4.tcp_fastopen" = 3;
    "net.ipv4.tcp_tw_reuse" = 1;
    "net.ipv4.tcp_fin_timeout" = 30;
    "net.ipv4.tcp_max_syn_backlog" = 8192;
    "net.ipv4.route.max_size" = 524288;

    # IPv6 and conntrack
    "net.ipv6.conf.all.forwarding" = true;
    "net.netfilter.nf_conntrack_max" = 262144;
    "net.nf_conntrack_max" = 262144;

    # VM tuning
    "vm.swappiness" = 10;
    "vm.page-cluster" = 0;
    "vm.max_map_count" = 1048576;
  };

  services.hellas = {
    enable = true;
    openFirewall = true;
    port = 31145;
    # downloadPolicy = "eager";
    executePolicy = "allow(hf/HuggingFaceTB/SmolLM2-135M-Instruct)";
    graffiti = "trex";
    preloadWeights = [
      "Qwen/Qwen3.5-0.8B"
    ];
    # trustedCallerPublicKeys = [
    #   "03561852f0eda08f4b842cc800cf68845af1286c4881bf826a29fe87439e27eb08"
    #   "02edec6b26cae32e9cd0bfbb90594066e60d0f9973b001af3ee15752162ab7dd99"
    # ];
    # fetchCodexResponses = true;
    # fetchCodexAuthPath = "/var/lib/hellas/.hellas/codex-auth.json";
    otel = {
      endpoint = "https://jaeger.lsd-ag.ch/v1/traces";
      serviceName = "executor-trex";
      sampleRate = 1;
      headers = {
        CF-Access-Client-Id = "312310f4c9c50c2bf9ee7e801d92a9ed.access";
        CF-Access-Client-Secret = "91bcfc62a1b4058b3c82b31560c146d7761b7cb1a507ff68b26d745d0650f6a8";
      };
    };
    # Slim (non-candle) gateway routing OpenAI/Anthropic requests over the
    # Hellas network. Replaced the llama.cpp proxy when the dGPU was pulled.
    gateway = {
      enable = true;
      host = network.primaryIp self;
      port = 8083;
      openFirewall = true;
    };
  };

  services.hermes-agent = {
    enable = true;
    package = inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.hermes-agent;
    user = "grw";
    group = "users";
    createUser = false;
    createGroup = false;
    stateDir = "/home/grw/.hermes";
    homeDir = "/home/grw";
  };

  # Signal transport for hermes-gateway. signal-cli runs as an HTTP daemon
  # that the gateway polls; account state lives in ~grw/.local/share/signal-cli
  # (link once with `signal-cli link -n HermesAgent`). 8080 is qBittorrent,
  # so the daemon listens on 8082 (8083 is the hellas gateway).
  systemd.services.signal-cli-daemon = {
    description = "signal-cli HTTP daemon for Hermes gateway";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "grw";
      Group = "users";
      ExecStart = "${pkgs.signal-cli}/bin/signal-cli daemon --http 127.0.0.1:8082";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  environment.systemPackages = with pkgs; [
    signal-cli
    qrencode # render the signal-cli link URI as a terminal QR code
    python312Packages.huggingface-hub
    # Scriptable BIOS setup vars (PCIe bifurcation for the 4x4x4x4 riser in
    # slot 2, etc.). Build the map once from a BIOS dump with
    # `bios-setup-var build-db <rom> -o /var/lib/bios-setup-var/db.json`.
    bios-setup-var
  ];

  # This box runs an aggressive CPU + memory overclock and is the fleet's NAS
  # and NFS root, so RAS visibility is not optional: rasdaemon logs per-DIMM
  # correctable/uncorrectable ECC counts and decodes SMCA machine checks to
  # /var/lib/rasdaemon (persistent root here — no impermanence). A rising CE
  # count on one DIMM is the early-warning that the memory OC has gone
  # marginal (usually thermal); WHEA/MCE catches core/fabric-OC errors that
  # ECC does NOT cover. `ras-mc-ctl --summary` / `--error-count` to read.
  hardware.rasdaemon.enable = true;

  # Trex is the sole writer for the Strix model tree. The Strix machines mount
  # this cache read-only, which avoids cross-node Hub/file-lock races during
  # distributed vLLM startup.
  systemd.services.strix-model-qwen3-0-6b = {
    description = "Pre-stage Qwen3-0.6B for the Strix vLLM cluster";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "models.mount" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "grw";
      Group = "users";
      RemainAfterExit = true;
      Environment = [
        "HF_HOME=/models/.cache/huggingface"
        "HF_HUB_DISABLE_TELEMETRY=1"
      ];
      ExecStart = "${pkgs.python312Packages.huggingface-hub}/bin/hf download Qwen/Qwen3-0.6B --revision c1899de289a04d12100db370d81485cdf75e47ca --cache-dir /models/.cache/huggingface/hub";
    };
  };

  nix.settings.build-cores = lib.mkDefault 48;
  nix.settings.max-jobs = lib.mkDefault 4;

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd

    inputs.nix-strix-halo.nixosModules.default
    inputs.nix-strix-halo.nixosModules.benchmark-runner
    inputs.nix-strix-halo.nixosModules.rpc-server

    inputs.hellas.nixosModules.default

    ../../../containers/arr-servers.nix
    # ../../../containers/gh-runner-grw.nix

    ../../../profiles/common.nix
    ../../../profiles/headless.nix
    ../../../profiles/home.nix
    ../../../profiles/development.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/zfs.nix
    ../../../profiles/nas.nix
    ../../../profiles/netboot-server.nix
    ../../../profiles/crypto
    ../../../profiles/logserver.nix

    ../../../services/nginx.nix
    ../../../services/grafana.nix
    ../../../services/victoriametrics.nix
    ../../../services/jellyfin.nix
    ../../../services/p2pool.nix
    ../../../services/p2pool-exporter.nix
    ../../../services/buildfarm-executor.nix
    ../../../services/hydra-builder-slave.nix
    ../../../services/buildfarm-slave.nix
    ../../../services/virt/host.nix
    ../../../services/virt/vfio.nix
    ../../../services/apple-health-ingester.nix

  ];

  deployment = {
    targetHost = network.primaryIp self;
    targetUser = "grw";
    # buildOnTarget = true;
  };

  hardware.cpu.amd.ryzen-smu.enable = false;
  programs.ryzen-monitor-ng.enable = false;

  sops.secrets.hf-token = mkSecret "hf-token" { };
  sops.templates."hellas-env".content = ''
    HF_TOKEN=${config.sops.placeholder."hf-token"}
  '';
  systemd.services.hellas.serviceConfig.EnvironmentFile =
    config.sops.templates."hellas-env".path;

  sops.secrets.qui-session = mkSecret "qui-session" { };
  sops.secrets.mosquitto-password = mkSecret "mosquitto-password" {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  services.qui = {
    enable = true;
    openFirewall = true;
    secretFile = "/run/secrets/qui-session";
    settings = {
      host = "0.0.0.0";
      port = 7476;
    };
  };

  # Ensure qbittorrent waits for bpool media mount
  systemd.services.qbittorrent = {
    bindsTo = [ "mnt-Media.mount" ];
    after = [ "mnt-Media.mount" ];
  };

  services.qbittorrent = {
    enable = true;
    # Use the profile root at /var/lib/qbittorrent so qBittorrent
    # places config under /var/lib/qbittorrent/qBittorrent/config
    # and data under /var/lib/qbittorrent/data (avoids double-nesting).
    profileDir = "/var/lib/qbittorrent";
    webuiPort = 8080;
    torrentingPort = 17026;
    openFirewall = true;
  };

  fileSystems."/var/lib/qbittorrent" = {
    device = "pool3d/root/downloads";
    fsType = "zfs";
    options = [ "nofail" ];
  };

  fileSystems."/models" = {
    device = "pool3d/root/models";
    fsType = "zfs";
    options = [ "nofail" ];
  };

  system.stateVersion = "24.11";

  fileSystems."/dev/hugepages1G" = {
    device = "hugetlbfs";
    fsType = "hugetlbfs";
    options = [ "pagesize=1G" "size=1G" "mode=1777" ];
  };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "schedutil";
  };

  services.max-perf = {
    enable = true;
    description = "trex IPMI fan full-speed mode";
    activeScript = ''
      normalize_bytes() {
        ${pkgs.coreutils}/bin/tr -s '[:space:]' ' ' \
          | ${pkgs.gnused}/bin/sed 's/^ //; s/ $//' \
          | ${pkgs.coreutils}/bin/tr '[:lower:]' '[:upper:]'
      }

      validate_hex_bytes() {
        expected_count="$1"
        shift

        count=0
        for byte in "$@"; do
          case "$byte" in
            [0-9A-F][0-9A-F]) ;;
            *)
              echo "max-perf: invalid IPMI byte '$byte'" >&2
              exit 1
              ;;
          esac
          count=$((count + 1))
        done

        if [ "$count" -ne "$expected_count" ]; then
          echo "max-perf: expected $expected_count IPMI bytes, got $count" >&2
          exit 1
        fi
      }

      # ASRock Rack AST2600 OEM fan control:
      # - read mode: 0x3a 0xd0 0x12
      # - set mode:  0x3a 0xd0 0x11 <16 bytes>
      # - read duty: 0x3a 0xd0 0x0f
      # - set duty:  0x3a 0xd0 0x0e <16 bytes>
      raw_mode="$(${pkgs.ipmitool}/bin/ipmitool -I open raw 0x3a 0xd0 0x12 | normalize_bytes)"
      raw_duty="$(${pkgs.ipmitool}/bin/ipmitool -I open raw 0x3a 0xd0 0x0f | normalize_bytes)"

      set -- $raw_mode
      validate_hex_bytes 16 "$@"
      restore_mode_cmd="${pkgs.ipmitool}/bin/ipmitool -I open raw 0x3a 0xd0 0x11"
      for byte in "$@"; do
        restore_mode_cmd="$restore_mode_cmd 0x$byte"
      done

      set -- $raw_duty
      validate_hex_bytes 16 "$@"
      restore_duty_cmd="${pkgs.ipmitool}/bin/ipmitool -I open raw 0x3a 0xd0 0x0e"
      for byte in "$@"; do
        restore_duty_cmd="$restore_duty_cmd 0x$byte"
      done

      # Restore duty first, then mode (tested on trex).
      ${pkgs.coreutils}/bin/printf '%s || true\n' "$restore_duty_cmd" >> "$MAX_PERF_RESTORE_SCRIPT"
      ${pkgs.coreutils}/bin/printf '%s || true\n' "$restore_mode_cmd" >> "$MAX_PERF_RESTORE_SCRIPT"

      # 0x02 = manual mode for each fan entry (16 entries), then 100%% duty (0x64).
      ${pkgs.ipmitool}/bin/ipmitool -I open raw 0x3a 0xd0 0x11 \
        0x02 0x02 0x02 0x02 0x02 0x02 0x02 0x02 \
        0x02 0x02 0x02 0x02 0x02 0x02 0x02 0x02 >/dev/null
      ${pkgs.ipmitool}/bin/ipmitool -I open raw 0x3a 0xd0 0x0e \
        0x64 0x64 0x64 0x64 0x64 0x64 0x64 0x64 \
        0x64 0x64 0x64 0x64 0x64 0x64 0x64 0x64 >/dev/null
    '';
    mqtt = {
      enable = true;
      host = network.routerIp;
      username = "rw";
      passwordFile = config.sops.secrets.mosquitto-password.path;
    };
  };

  systemd.services.max-perf-mqtt = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
  };

  # L2ARC tuning for bpool Optane cache - no write rate limit
  boot.extraModprobeConfig = ''
    options zfs l2arc_write_max=9223372036854775807
  '';

  boot = {
    kernelModules = [
      "ipmi_devintf"
      "ipmi_si"
    ];
    kernelParams = [
      # Serial console for BMC Serial-over-LAN. Keep tty0 first so the ASPEED
      # video console still shows everything (BMC HTML5 KVM); ttyS1 last makes
      # it /dev/console and gets a login getty. ttyS1 (0x2F8 = COM2) is the
      # ASRock-Rack SOL UART by convention — confirm against the ACPI SPCR
      # table once BIOS Console Redirection (menu 3.4.8, COM0, VT-UTF8,
      # 115200 8N1) is enabled, and swap to ttyS0 here if SPCR says 0x3F8.
      "console=tty0"
      "console=ttyS1,115200n8"
      "amd_pstate=passive"
      "hugepagesz=1G"
      "hugepages=1"
      "transparent_hugepages=madvise"
      # amd_iommu handled by VFIO config (services/virt/vfio.nix)
      "pci=realloc=off" # fixes: only 7 of 8 pex downstream work
      "pcie=pcie_bus_perf"
      "pcie_acs_override=downstream"
      "pcie_ports=native"
      "zswap.enabled=1"
      "zswap.compressor=zstd"
      "zswap.max_pool_percent=20"
    ];
    initrd = {
      kernelModules = [ "mlx5_core" "lm92" ];
      services.udev.packages = [ mlxUdevRules ];
      systemd = {
        storePaths = [
          "${pkgs.iproute2}/bin/devlink"
          "${pkgs.ethtool}/bin/ethtool"
          "${mlxVfName}"
        ];
        services.mlx5-switchdev = {
          description = "Configure Mellanox switchdev and SR-IOV in initrd";
          wantedBy = [ "initrd.target" ];
          before = [ "initrd-switch-root.target" ];
          after = [ "systemd-udev-trigger.service" "systemd-udevd.service" ];
          wants = [ "systemd-udev-trigger.service" "systemd-udevd.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [
            pkgs.coreutils
            pkgs.ethtool
            pkgs.gnugrep
            pkgs.iproute2
            config.boot.initrd.systemd.package
          ];
          script = ''
            set -eu

            PF_MAC=${mlxPfMac}
            VF_COUNT=${toString mlxVfCount}
            COMBINED_CHANNELS=32

            find_pf() {
              for netdev in /sys/class/net/*; do
                [ -e "$netdev/address" ] || continue
                [ "$(cat "$netdev/address")" = "$PF_MAC" ] || continue
                basename "$netdev"
                return 0
              done
              return 1
            }

            PF=""
            for _ in 1 2 3 4 5 6 7 8 9 10; do
              if PF="$(find_pf)"; then
                break
              fi
              udevadm settle --timeout=2 || true
              sleep 1
            done

            if [ -z "$PF" ]; then
              echo "Mellanox PF with MAC $PF_MAC not found"
              exit 1
            fi

            PCI_BDF="$(basename "$(readlink -f "/sys/class/net/$PF/device")")"
            PCI_SYS="/sys/bus/pci/devices/$PCI_BDF"
            PCI_DEV="pci/$PCI_BDF"

            echo 0 > "$PCI_SYS/sriov_numvfs" || true
            sleep 1

            devlink dev eswitch set "$PCI_DEV" mode legacy || true
            sleep 1

            if PF="$(find_pf)"; then
              ethtool -L "$PF" combined "$COMBINED_CHANNELS" || true
            fi

            devlink dev eswitch set "$PCI_DEV" mode switchdev
            sleep 2

            echo "$VF_COUNT" > "$PCI_SYS/sriov_numvfs"

            for _ in $(seq 1 10); do
              udevadm settle --timeout=1 || true

              rep_count=0
              for rep in /sys/class/net/${mlxPfName}r*; do
                [ -e "$rep" ] || continue
                rep_count=$((rep_count + 1))
              done

              vf_count=0
              for vf in /sys/class/net/${mlxPfName}v*; do
                [ -e "$vf" ] || continue
                vf_count=$((vf_count + 1))
              done

              [ "$rep_count" -ge "$VF_COUNT" ] && [ "$vf_count" -ge "$VF_COUNT" ] && break
              sleep 1
            done

            echo "Mellanox switchdev initialized on $PCI_DEV with $VF_COUNT VFs"
          '';
        };
      };
    };
    blacklistedKernelModules = [ "nouveau" "i915" ];
  };

  # Stable names for the ConnectX-4 PF and its switchdev VF representors.
  # Keyed on phys_switch_id (ASIC-stable) so they don't follow the PCIe bus.
  # Numbered 75- so it runs before 80-net-setup-link.rules, whose predictable
  # naming only fires when NAME is still empty. VFs have no phys_switch_id, so a
  # helper derives their mlxlan0vN names from the PF virtfnN symlinks.
  services.udev.packages = [ mlxUdevRules ];
  services.udev.extraRules = ''
    # Auto-authorize IOCREST 40Gbps Thunderbolt NIC on plug-in
    ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{unique_id}=="c8010000-00b1-bd08-2230-ad1cc6200123", ATTR{authorized}="1"
  '';

  # OVS for Mellanox switchdev mode
  virtualisation.vswitch.enable = true;

  networking.vswitches.ovs-mlx = {
    interfaces = {
      # Uplink (PF) + VF representors — stable switchdev names (see mlx* lets).
      ${mlxPfName} = { };
    } // lib.genAttrs mlxRepNames (_: { }) // lib.genAttrs i40eNames (_: { }) // {
      # Internal port for host
      ovs-host = {
        type = "internal";
      };
    };
  };

  networking.useDHCP = false;

  # Set jumbo MTU on OVS internal port (must be done via ovs-vsctl)
  systemd.services.ovs-host-mtu = {
    description = "Set OVS ovs-host interface MTU to 9000";
    after = [ "ovsdb-server.service" "ovs-vswitchd.service" "ovs-mlx-netdev.service" ];
    requires = [ "ovs-vswitchd.service" "ovs-mlx-netdev.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Wait for interface to appear in OVS (max 30 seconds)
      for i in $(seq 1 30); do
        if ${pkgs.openvswitch}/bin/ovs-vsctl list interface ovs-host >/dev/null 2>&1; then
          ${pkgs.openvswitch}/bin/ovs-vsctl set interface ovs-host mtu_request=9000
          echo "Set ovs-host MTU to 9000"
          exit 0
        fi
        echo "Waiting for ovs-host interface... ($i/30)"
        sleep 1
      done
      echo "ERROR: ovs-host interface not found after 30 seconds"
      exit 1
    '';
  };

  services.avahi.allowInterfaces = lib.mkForce [ "ovs-host" ];

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "x86_64-windows"
  ];

  swapDevices = [
    { device = "/dev/disk/by-uuid/c4052b76-2ab1-4715-b55d-07b0720d58cc"; }
    { device = "/dev/disk/by-uuid/30927806-c236-42dc-a198-462b757fd80f"; }
    { device = "/dev/disk/by-uuid/74122086-e876-4846-803f-62147dd54895"; }
    { device = "/dev/disk/by-uuid/3abe0f94-1b4b-40bf-8023-9cedaa4e8485"; }
    { device = "/dev/disk/by-uuid/7f89d211-da19-4b27-864b-aa16761af3b5"; }
    { device = "/dev/disk/by-uuid/84df5a65-7f52-4350-84f2-9c38fb4747bb"; }
    { device = "/dev/disk/by-uuid/9c8d8671-759b-48ba-a4e9-92cc3c20f8cb"; }
    { device = "/dev/disk/by-uuid/d8aac565-6df0-42be-bb6f-d8f42cb8cd81"; }
  ];

  fileSystems."/" = {
    device = "pool3d/root/trex-root";
    fsType = "zfs";
    options = [ "atime" "relatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/TREXBOOTA";
    fsType = "vfat";
    options = [ "iocharset=iso8859-1" "fmask=0077" "dmask=0077" ];
  };

  boot.loader.systemd-boot.extraInstallCommands = ''
    backup_esp=/dev/disk/by-label/TREXBOOTB

    if [ -e "$backup_esp" ]; then
      backup_mount="$(${pkgs.coreutils}/bin/mktemp -d /tmp/trex-boot-b.XXXXXX)"
      cleanup_backup_esp() {
        ${pkgs.util-linux}/bin/umount "$backup_mount" 2>/dev/null || true
        ${pkgs.coreutils}/bin/rmdir "$backup_mount" 2>/dev/null || true
      }
      trap cleanup_backup_esp EXIT

      ${pkgs.util-linux}/bin/mount -t vfat \
        -o iocharset=iso8859-1,fmask=0077,dmask=0077 \
        "$backup_esp" "$backup_mount"
      ${pkgs.rsync}/bin/rsync -aH --delete \
        --no-owner --no-group --no-perms \
        --exclude=loader/random-seed \
        /boot/ "$backup_mount/"
      cleanup_backup_esp
      trap - EXIT
    else
      echo "TREXBOOTB backup ESP not present; skipping mirror sync"
    fi
  '';

  fileSystems."/home/grw" = {
    device = "pool3d/root/grw-home";
    fsType = "zfs";
    options = [ "noatime" "nofail" ];
  };

  # Bind mount for NFSv4 export
  fileSystems."/export/grw" = {
    device = "/home/grw";
    fsType = "none";
    options = [ "bind" ];
  };

  services = {
    fstrim.enable = true;
    fwupd.enable = true;
    hardware.openrgb.enable = true;
    iperf3.enable = true;

    # ZFS snapshot management - short retention on source
    sanoid =
      let
        excluded = {
          autosnap = false;
          hourly = 0;
          daily = 0;
          weekly = 0;
          monthly = 0;
        };
      in
      {
        enable = true;
        interval = "hourly";
        datasets."pool3d" = {
          recursive = true;
          autosnap = true;
          hourly = 24;
          daily = 7;
          weekly = 0;
          monthly = 0;
        };
        datasets."pool3d/root/tari" = excluded;
        datasets."pool3d/root/monero" = excluded;
      };

    # ZFS replication to fuckup
    syncoid =
      let
        excludedDatasets = [ "tari" "monero" ];
      in
      {
        enable = true;
        interval = "hourly";
        sshKey = "/var/lib/syncoid/.ssh/id_ed25519";
        commands."pool3d-to-archive" = {
          source = "pool3d";
          target = "root@fuckup:archive/pool3d";
          recursive = true;
          sendOptions = "w";
          extraArgs = lib.concatMap (d: [ "--exclude" d ]) excludedDatasets;
        };
      };
  };

  networking = {
    hostName = "trex";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    nameservers = [ network.routerIp ];
    firewall = {
      enable = false;
      allowedTCPPorts = [
        2049 # NFS
        111 # rpcbind/portmapper
        88 # Kerberos authentication
        749 # Kerberos administration
        4000 # statd
        4001 # lockd
        4002 # mountd
        17026 # qbittorrent
        8083 # Hellas gateway
        18089 # monerod
        20048 # NFSv4 callback
      ];
      allowedUDPPorts = [
        2049 # NFS
        111 # rpcbind/portmapper
        88 # Kerberos authentication
        4000 # statd
        4001 # lockd
        4002 # mountd
        17026 # qbittorrent
        18089 # monerod
        20048 # NFSv4 callback
      ];
    };
  };

  services.open-webui = {
    enable = true;
    host = network.primaryIp self;
    port = 11111;
    openFirewall = true;
    environment = {
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
      ENABLE_OLLAMA_API = "False";
      ENABLE_OPENAI_API = "True";
      # Hellas gateway (llama.cpp left with the dGPU).
      OPENAI_API_BASE_URL = "http://${network.primaryIp self}:8083/v1";
      OPENAI_API_KEY = "sk-no-key-required";
      WEBUI_URL = "https://${network.publicFqdn "open-webui"}";
      HOME = "/var/lib/open-webui";
      XDG_CACHE_HOME = "/var/lib/open-webui/.cache";
    };
  };

  services.nix-serve = {
    enable = true;
    secretKeyFile = config.sops.secrets.nix-cache-key.path;
  };

  sops.secrets.nix-cache-key = mkSecret "nix-cache-key" { };

  systemd.network =
    let
      bridgeName = "br0.lan";
    in
    {
      enable = true;
      wait-online.anyInterface = true;
      links = {
        # PF: buffer settings. Matched by permanent MAC so it applies
        # regardless of the kernel's pre-rename name.
        "20-mlx5-pf" = {
          matchConfig.PermanentMACAddress = mlxPfMac;
          linkConfig = {
            Name = mlxPfName;
            RxBufferSize = 8192;
            TxBufferSize = 8192;
          };
        };
      } // lib.mapAttrs'
        (name: mac: lib.nameValuePair "20-${name}" {
          matchConfig.PermanentMACAddress = mac;
          linkConfig.Name = name;
        })
        i40ePorts;
      netdevs = {
        "20-${bridgeName}" = {
          netdevConfig = {
            Kind = "bridge";
            Name = bridgeName;
          };
          bridgeConfig = {
            STP = true;
          };
        };
      };
      networks = {
        # BMC virtual USB NIC (AMI MegaRAC, idVendor 046b) — the in-band
        # Redfish/IPMI host interface exposed by the AST2600. SMBIOS type 42
        # pins the host side at 169.254.0.18/16 and the BMC at 169.254.0.17
        # (Redfish on :443, SSH on :22, no DHCP server on the link). Priority
        # 20 beats the thunderbolt-bridge profile's 49-bmc-exclude (Unmanaged)
        # and 50-cdc-ether (Bridge=br0.lan), mirroring how the router pins its
        # NanoKVM with 20-nanokvm. NB: unlike the NanoKVM, the BMC does NOT
        # route between this USB link and its dedicated LAN, so this is a
        # host->BMC management path only, not an inbound backdoor to trex. The
        # out-of-band console to trex is the BMC LAN (192.168.23.10) via IPMI
        # SOL / iKVM.
        "20-bmc-usb" = {
          matchConfig = {
            Driver = "cdc_ether";
            Property = "ID_VENDOR_ID=046b";
          };
          address = [ "169.254.0.18/16" ];
          networkConfig = {
            DHCP = "no";
            LinkLocalAddressing = "ipv6";
            IPv6AcceptRA = false;
          };
          linkConfig.RequiredForOnline = "no";
        };

        # Mellanox PF (100G): bring up for OVS with jumbo MTU
        "10-lan-100g" = {
          matchConfig.Name = mlxPfName;
          linkConfig = {
            ActivationPolicy = "up";
            RequiredForOnline = "no";
            MTUBytes = "9000";
          };
        };
        # VFs: don't configure (will be passed to containers). They carry no
        # phys_switch_id so they keep their enpXsYvZ names.
        "10-mlx5-vf" = {
          matchConfig = {
            Driver = "mlx5_core";
            Name = "${mlxPfName}v*";
          };
          linkConfig.Unmanaged = "yes";
        };
        # VF representors: bring up for OVS
        "10-mlx5-rep" = {
          matchConfig.Name = "${mlxPfName}r*";
          linkConfig = {
            ActivationPolicy = "up";
            RequiredForOnline = "no";
          };
        };
        # OVS internal port for host connectivity
        "10-ovs-host" = {
          matchConfig.Name = "ovs-host";
          address = [ (network.cidrOf "lan" self.addresses.lan) ];
          routes = [{ Gateway = network.routerIp; }];
          networkConfig = {
            DNS = network.routerIp;
          };
          # Only autoconfigure SLAAC from our ISP's delegated /64. Rogue RAs from
          # other devices on the LAN (e.g. Apple devices acting as Tailscale
          # subnet routers) advertise ULA prefixes that briefly get autoconfigured
          # and then trigger ICMPv6 "advertised our address" dmesg spam when the
          # host's own NAs are reflected back through OVS/the Mellanox eswitch.
          ipv6AcceptRAConfig = {
            PrefixAllowList = "2a02:168:58b4::/64";
          };
          linkConfig.RequiredForOnline = "routable";
        };
        # IOCREST 40Gbps TB NIC (AQC113, tunneled PCIe via Thunderbolt): bridge to LAN
        "30-aqc-bridge" = {
          matchConfig.Driver = "atlantic";
          networkConfig.Bridge = bridgeName;
          linkConfig = {
            MTUBytes = "9000";
            RequiredForOnline = "no";
          };
        };

        # br0.lan for non-Mellanox interfaces (Intel, thunderbolt, USB) - no IP, just L2
        "05-${bridgeName}" = {
          matchConfig.Name = bridgeName;
          bridgeConfig = { };
          networkConfig = {
            ConfigureWithoutCarrier = true;
            IgnoreCarrierLoss = true;
          };
          linkConfig.RequiredForOnline = "no";
        };
      };
    };

  # Create needed directories (no-ops if already exist)
  systemd.tmpfiles.rules = [
    # qBittorrent profile + incomplete on SSD (pool3d)
    "d /var/lib/qbittorrent 0775 qbittorrent qbittorrent -"
    "d /var/lib/qbittorrent/incomplete 0775 qbittorrent qbittorrent -"

  ];
}
