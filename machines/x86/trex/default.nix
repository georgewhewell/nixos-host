{
  pkgs,
  lib,
  inputs,
  mkSecret,
  config,
  network,
  ...
}: let
  self = network.hosts.trex;
  # The BlueField's LAN address, used only as the gateway to its private DPU
  # address below. Was named beegfsMgmtd* when that host ran BeeGFS mgmtd;
  # BeeGFS is retired and the route has nothing to do with it.
  bluefield2LanIp = network.ipOf "lan" network.hosts.bluefield2.addresses.lan;

  # ConnectX-4, plain (legacy) mode. Pin the PF name to its permanent MAC so it
  # survives PCIe re-enumeration -- the card's bus number moves whenever the
  # PCIe tree is re-walked (e.g. toggling the BMC's shared-NIC mode), and with
  # `pci=realloc=off` kernel-assigned enpXsY names move with it.
  #
  # 2026-08-08: switchdev + SR-IOV + OVS removed entirely. The eswitch had 7
  # VFs and 7 representors, of which exactly one VF was in use -- and that one
  # existed only to give *this host* an RDMA endpoint, because an OVS internal
  # port has no verbs device. In switchdev mode the PF itself has no verbs
  # device either, so the VF was a workaround for damage the eswitch caused.
  # Nothing else consumed a VF; the two i40e ports OVS also bridged are
  # unplugged (carrier=0, zero bytes). With the eswitch gone the PF carries
  # trex's addresses directly and serves RoCE natively, which removes the
  # hardware/software split-forwarding path -- the leading suspect for the
  # RoCE packet reordering (huge out_of_sequence with zero switch drops) that
  # pinned NVMe-oF throughput near 300 MiB/s on a 100G fabric.
  mlxPfMac = "50:6b:4b:0d:24:86";
  mlxPfName = "mlxlan0";
  # SR-IOV in LEGACY mode (2026-08-09). VFs are what gives a container its own
  # identity on the wire -- and, unlike switchdev, legacy mode keeps a verbs
  # device on both the PF and every VF, so containers can do RDMA and the host
  # still serves RoCE natively. The NIC's embedded switch does MAC-based L2
  # forwarding in hardware: no representors, no OVS, no software datapath.
  # Four VFs, not seven: only one is consumed today, and the old VF7 timed out
  # in mlx5_core ENABLE_HCA and cost a minute of boot.
  mlxVfCount = 4;
  # VFs carry no phys_switch_id, so derive mlxlan0vN from the PF's virtfnN
  # symlinks. Without this they take PCI-enumeration names and the container's
  # `interfaces = ["mlxlan0v0"]` would bind whichever VF happened to enumerate
  # first.
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
    name = "75-mlx-vf-names";
    destination = "/etc/udev/rules.d/75-mlx-vf-names.rules";
    text = ''
      SUBSYSTEM=="net", ACTION=="add", DRIVERS=="mlx5_core", ATTRS{vendor}=="0x15b3", ATTRS{device}=="0x1014", PROGRAM="${mlxVfName} %p", NAME="%c"
    '';
  };
  # Pinned VF MACs. VF0 takes the arr-servers inventory identity; the driver
  # otherwise randomises every VF MAC on each boot, which is why that container
  # never actually had a stable identity on the network.
  mlxVfMacs = [
    network.hosts."arr-servers".mac
    "52:6b:4b:0d:24:e1"
    "52:6b:4b:0d:24:e2"
    "52:6b:4b:0d:24:e3"
  ];

  # 10G Intel ports, MAC-pinned for the same reason. Currently unplugged.
  i40ePorts = {
    i40e0 = "9c:6b:00:57:30:60";
    i40e1 = "9c:6b:00:57:30:61";
  };
in {
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
    # Host half of the CRS804's lossless RoCE policy: without this every RoCE
    # packet leaves on priority 0 and the switch's PFC/ECN policy on TC3 is
    # inert. See modules/roce-qos.nix.
    roceQos = {
      enable = true;
      interface = mlxPfName;
      # trex faces the CRS510, which has no PFC at all, so 802.3x pause is the
      # only backpressure available on this leg -- that switch is already
      # pausing this port. The strix nodes face the PFC-capable CRS804 and
      # deliberately leave it off.
      globalPause = true;
    };
    # Ephemeral tmpfs root (2026-07-24); explicit persistence list below.
    # sops/ssh host identity moves to /persist/etc/ssh via profiles/sops.nix.
    impermanence.enable = true;
    home-manager = {
      enable = true;
      enableVscodeServer = true;
    };
    xmrig = {
      # Parked with the chain services (its upstream is the local p2pool).
      enable = false;
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

  # Chain services un-parked 2026-08-11. They were stopped during the pool3d
  # retirement because their random-IO workloads did not belong on bpool's HDD
  # stripe; they now live on dedicated btrfs subvolumes on the nand4 NVMe
  # array (chains/{monero,tari,p2pool}), with the ~416G of dormant state
  # copied across rather than re-synced from the network.

  # services/p2pool.nix still declares the encrypted merge-mining environment
  # while the daemon is parked. Retain its account so sops can install that
  # secret with the intended ownership on a fresh impermanent root.
  users.users.p2pool = {
    isSystemUser = true;
    group = "p2pool";
    home = "/var/lib/p2pool";
  };
  users.groups.p2pool = {};

  systemd.timers.gcp-ddns.timerConfig.OnActiveSec = lib.mkForce "15min";
  systemd.services.gcp-ddns.serviceConfig.TimeoutStartSec = "15min";

  # 7985WX - big parallel builder
  nix.settings = {
    system-features = ["gccarch-znver4" "kvm" "big-parallel" "nixos-test"];
    download-buffer-size = 104857600; # 100 MiB
    http-connections = 64;
    # buildfarm-executor turns this on for CI rebuild speed, but on trex it
    # pins the build-time closure of ~450 result/.direnv roots (~1T live
    # store that nix-collect-garbage -d can never reclaim). Root must stay
    # lean enough for the 2-disk Optane pair replacing pool3d.
    keep-outputs = lib.mkForce false;
    # Sign locally-built store paths with our cache key so `nix copy` to
    # strix-1/strix-2 (which trust this key via modules/nix.nix) is
    # accepted without --no-check-sigs.
    secret-key-files = [config.sops.secrets.nix-cache-key.path];
  };

  # Strix-2 remains netbooted with a read-only /nix/store, so it cannot act as
  # a writable Nix builder for trex. Strix-1 boots from its local NVMe again.
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
    # Placeholder assurance terms (mirrors nix/tests/e2e.nix) until the
    # attested-execution plan drops these flags.
    assuranceCodec = "tpm2.quote.v1";
    assurancePolicy = "0000000000000000000000000000000000000000000000000000000000000000";
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

  # Hermes and its Signal transport are intentionally disabled. OMP is the
  # orchestrator used on trex; retaining the unused gateway would keep an
  # unrelated Python agent in every system and Home Manager closure.
  services.hermes-agent.enable = false;

  # Kimi Code web UI (`kimi web`). Bound to 127.0.0.1 and published only through
  # the TLS vhost in services/nginx.nix, which restricts access to the LAN and
  # WG clients (the router terminates WG and routes 192.168.24.0/24 into the
  # LAN). Bearer-token auth stays on; the token is printed to the journal at
  # startup and lives in ~grw/.kimi-code/server.token.
  #
  # 2026-07-30: this had been changed to bind the LAN address directly with
  # trex's own hostnames as --allowed-host, which bypassed the vhost and its
  # TLS entirely. That was my regression -- I rsynced a stale working tree over
  # this repo -- and is restored here from the deployed generation 45.
  systemd.services.kimi-server = {
    description = "Kimi Code server (REST + WebSocket + web UI)";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    # ~grw/.kimi-code holds the server token, OAuth credentials and sessions.
    unitConfig.RequiresMountsFor = "/home/grw";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      User = "grw";
      Group = "users";
      Environment = ["KIMI_CODE_NO_AUTO_UPDATE=1"];
      ExecStart = let
        kimi-code = inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.kimi-code;
      in
        "${kimi-code}/bin/kimi web --no-open --log-level info --port 58627 "
        + "--host 127.0.0.1 "
        + "--allowed-host ${network.fqdn "kimi"}";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # opencode headless server (`opencode serve`). Mirrors kimi-server, but note
  # the sharp difference: opencode's serve API has NO authentication and can
  # execute shell commands, so binding it to the LAN address means anyone on
  # the LAN or a WG client can run commands as grw. This LAN binding is an
  # explicit, accepted decision (2026-07-21) for a trusted home LAN — revisit
  # (localhost-only + an authenticated proxy) before this box ever faces a
  # less-trusted network. ~grw/.local/share/opencode holds auth and sessions.
  systemd.services.opencode-server = {
    description = "opencode server (headless REST API)";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    unitConfig.RequiresMountsFor = "/home/grw";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      User = "grw";
      Group = "users";
      WorkingDirectory = "/home/grw";
      Environment = ["OPENCODE_DISABLE_AUTOUPDATE=1"];
      ExecStart = let
        opencode = inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
      in
        "${opencode}/bin/opencode serve --print-logs --log-level INFO "
        + "--port 58640 "
        + "--hostname ${network.primaryIp self}";
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
  # /var/lib/rasdaemon (bind-mounted from /persist — see the persistence
  # list). A rising CE
  # count on one DIMM is the early-warning that the memory OC has gone
  # marginal (usually thermal); WHEA/MCE catches core/fabric-OC errors that
  # ECC does NOT cover. `ras-mc-ctl --summary` / `--error-count` to read.
  hardware.rasdaemon.enable = true;

  nix.settings.build-cores = lib.mkDefault 48;
  nix.settings.max-jobs = lib.mkDefault 4;

  # Cluster-view dashboard for the strix nodes, provisioned into local grafana
  services.strix-halo.grafana-dashboards.enable = true;

  # LLM subscription quota metrics from ~grw CLI credentials,
  # scraped into local victoriametrics (services/victoriametrics.nix)
  services.llm-quota-exporter.enable = true;

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd

    inputs.nix-strix-halo.nixosModules.default
    inputs.nix-strix-halo.nixosModules.benchmark-runner
    inputs.nix-strix-halo.nixosModules.grafana-dashboards
    inputs.nix-strix-halo.nixosModules.rpc-server

    inputs.hellas.nixosModules.default

    # Parked 2026-08-08 for the switchdev -> legacy migration: this container
    # takes SR-IOV VF mlxlan0v0 into its namespace (its whole point -- its own
    # identity on the wire), and the migration temporarily removes SR-IOV so
    # the PF can be brought up clean and the RoCE ceiling measured without the
    # eswitch in the path. Restore together with legacy-mode VFs, and pin the
    # VF MAC at the same time: it is randomised on every boot today, so this
    # container's network identity was never actually stable.
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
    ../../../services/otel-collector.nix
    ../../../services/jellyfin.nix
    ../../../services/p2pool.nix
    ../../../services/p2pool-exporter.nix
    ../../../services/buildfarm-executor.nix
    ../../../services/hydra-builder-slave.nix
    ../../../services/buildfarm-slave.nix
    ../../../services/virt/host.nix
    ../../../services/virt/vfio.nix
    ../../../services/apple-health-ingester.nix
    # 905P shelf physically detached 2026-07-29: the module's initrd assembly
    # service aborts boot when the array is absent. Superseded by the SPDK
    # root-daemon path below; kept for reference.
    # ./optane-dm-stripe.nix
    # SPDK as a proper systemd root storage daemon (phase 1: daemon only,
    # no bdevs/mounts). See systemd.io/ROOT_STORAGE_DAEMONS.
    ./spdk-root-daemon.nix
    # Non-fatal stage-2 assembly: deterministic UUIDs, RAID/lvol discovery,
    # recoverable ublk mounts, and snapshot-only NVMe/RDMA export.
    ./spdk-storage-stack.nix
    # ConnectX-4 VF in the host namespace, so RDMA consumers have a verbs
    # device to bind on the fabric.
    # Safe read-only publication of the models volume (frozen snapshots, never
    # the live mount).
    ./spdk-models-snapshot.nix
  ];

  deployment = {
    targetHost = network.primaryIp self;
    targetUser = "grw";
    # buildOnTarget = true;
  };

  hardware.cpu.amd.ryzen-smu.enable = false;
  programs.ryzen-monitor-ng.enable = false;

  sops.secrets.hf-token = mkSecret "hf-token" {};
  sops.templates."hellas-env".content = ''
    HF_TOKEN=${config.sops.placeholder."hf-token"}
  '';
  systemd.services.hellas.serviceConfig.EnvironmentFile =
    config.sops.templates."hellas-env".path;

  # Password-protect the LAN-exposed opencode-server (see the unit above).
  # opencode reads OPENCODE_SERVER_PASSWORD from the environment; render it from
  # sops into an EnvironmentFile so the secret never lands in the store.
  sops.secrets.opencode-server-password = mkSecret "opencode-server-password" {};
  sops.templates."opencode-server-env".content = ''
    OPENCODE_SERVER_PASSWORD=${config.sops.placeholder."opencode-server-password"}
  '';
  systemd.services.opencode-server.serviceConfig.EnvironmentFile =
    config.sops.templates."opencode-server-env".path;

  # Give kimi-server a fixed password from sops instead of relying on the
  # random bearer token it prints at startup. kimi reads KIMI_CODE_PASSWORD
  # from the environment; render it from sops so it stays out of the store.
  sops.secrets.kimi-web-password = mkSecret "kimi-web-password" {};
  sops.templates."kimi-server-env".content = ''
    KIMI_CODE_PASSWORD=${config.sops.placeholder."kimi-web-password"}
  '';
  systemd.services.kimi-server.serviceConfig.EnvironmentFile =
    config.sops.templates."kimi-server-env".path;

  sops.secrets.qui-session = mkSecret "qui-session" {};
  sops.secrets.mosquitto-password = mkSecret "mosquitto-password" {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  # qBittorrent, qui and jellyfin moved into the arr-servers container
  # (2026-08-09) so all media services share one sandbox. The filesystems
  # below stay on the host: they are the bind-mount *sources* the container
  # consumes, and the container cannot mount them itself.

  fileSystems."/var/lib/qbittorrent" = {
    device = "bpool/trex/downloads";
    fsType = "zfs";
    options = ["nofail"];
  };

  # Volatile partial payloads live on the SPDK Optane array (optstore/qb-incomplete
  # lvol via ublk, XFS). The mount is established by the SPDK assembly flow, not
  # fstab, until the declarative phase-2 units land. Old zfs dataset
  # bpool/trex/downloads/incomplete retired 2026-07-29 (was empty).

  # /models moved off bpool/trex/models (2026-07-30): the model set now lives on
  # the SPDK Optane volume. The bpool dataset was migrated (verified byte-exact,
  # .cache deliberately left behind to be re-fetched on demand) and then
  # destroyed. Local writes land here rw. Strix clients consume only the pinned
  # snapshot over NVMe/RDMA; the remaining NFS export serves non-Strix clients.
  fileSystems."/models" = {
    device = "/mnt/optane/models";
    fsType = "none";
    options = ["bind" "nofail" "x-systemd.requires-mounts-for=/mnt/optane/models"];
  };

  system.stateVersion = "24.11";

  fileSystems."/dev/hugepages1G" = {
    device = "hugetlbfs";
    fsType = "hugetlbfs";
    options = ["pagesize=1G" "size=1G" "mode=1777"];
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
    after = ["sops-install-secrets.service"];
    wants = ["sops-install-secrets.service"];
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
      # ttyS1 first, tty0 last: the LAST console is primary, and with the BMC
      # SOL unreliable the local display must win (2026-07-29)
      "console=ttyS1,115200n8"
      "console=tty0"
      "amd_pstate=passive"
      "hugepagesz=1G"
      "hugepages=8"
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
    # No switchdev/SR-IOV setup here any more: the initrd used to flip the
    # eswitch and spawn 7 VFs before switch-root, which cost about a minute of
    # boot (VF7 timed out in ENABLE_HCA) and existed only to serve an eswitch
    # nothing used. Legacy mode needs nothing beyond the driver.
    initrd = {
      kernelModules = ["mlx5_core" "lm92"];
    };
    blacklistedKernelModules = ["nouveau" "i915"];
  };

  services.udev.packages = [mlxUdevRules];

  # Legacy-mode SR-IOV needs no eswitch flip -- just the VF count and stable
  # MACs. Ordered before network-pre so networkd and the container see named,
  # correctly-addressed VFs.
  systemd.services.mlx-sriov = {
    description = "Create ConnectX-4 VFs (legacy mode) and pin their MACs";
    wantedBy = ["multi-user.target"];
    before = ["network-pre.target" "container@arr-servers.service"];
    wants = ["network-pre.target"];
    after = ["sys-subsystem-net-devices-${mlxPfName}.device"];
    bindsTo = ["sys-subsystem-net-devices-${mlxPfName}.device"];
    path = [pkgs.iproute2 pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      pf=/sys/class/net/${mlxPfName}/device

      current=$(cat "$pf/sriov_numvfs")
      if [ "$current" != "${toString mlxVfCount}" ]; then
        echo 0 >"$pf/sriov_numvfs"
        echo ${toString mlxVfCount} >"$pf/sriov_numvfs"
        udevadm settle --timeout=10 || true
      fi

      ${lib.concatStrings (lib.imap0 (i: mac: ''
        ip link set ${mlxPfName} vf ${toString i} mac ${mac}
      '') mlxVfMacs)}
    '';
  };

  # The PF and the i40e ports are named by systemd.network links (below),
  # matched on permanent MAC -- no udev naming helper is needed without
  # representors and VFs to name.
  services.udev.extraRules = ''
    # Auto-authorize IOCREST 40Gbps Thunderbolt NIC on plug-in
    ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{unique_id}=="c8010000-00b1-bd08-2230-ad1cc6200123", ATTR{authorized}="1"
  '';

  networking.useDHCP = false;

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "x86_64-windows"
  ];

  # Ephemeral root (2026-07-24): tmpfs /, with /nix and /persist as btrfs
  # subvolumes striped over the two P1600X Optanes (native 4Kn media, so
  # sectorsize 4096; data raid0, metadata raid1, label "trexroot"). The old
  # zfs root generations stay bootable from the ESP menu until pool3d is
  # retired. flushoncommit: see profiles/router/usb-btrfs.nix for the
  # rename-crash-consistency war story; this box runs an aggressive OC.
  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    neededForBoot = true;
    options = ["mode=755" "size=16G"];
  };

  # The Nix store lives on `nand4` -- the 4x Corsair MP600 array -- not on the
  # Optane pair (2026-08-08). 212G of P1600X was simply too small: this box is
  # the fleet's netboot server, so /nix/store is also exported to every
  # diskless strix node (/export/nix-store in profiles/netboot-server.nix) and
  # therefore grows with the fleet, not with trex. It shares a filesystem with
  # /mnt/Home because the four Corsairs are whole-disk btrfs members with no
  # partition table, so a separate root filesystem there is not possible
  # without destroying Home.
  #
  # /persist stays on the Optanes, where ~10us random reads actually buy
  # something for postgres, docker and the journal -- and with the store gone
  # it has ~180G of headroom instead of 30G.
  #
  # nand4 is data raid0 across four drives with no redundancy, the same posture
  # as the Optane pair it replaces. The store is reproducible; note that
  # /persist is NOT covered by the syncoid jobs below, which replicate bpool.
  fileSystems."/nix" = {
    device = "/dev/disk/by-label/nand4";
    fsType = "btrfs";
    neededForBoot = true;
    options = ["subvol=/nix" "compress=zstd" "noatime" "flushoncommit"];
  };

  fileSystems."/persist" = {
    device = "/dev/disk/by-label/trexroot";
    fsType = "btrfs";
    neededForBoot = true;
    options = ["subvol=/persist" "compress=zstd" "noatime" "flushoncommit"];
  };

  # Big, cold /var trees live on bpool instead of the small fast root.
  fileSystems."/var/lib/nixos-containers" = {
    device = "/dev/disk/by-label/trexroot";
    fsType = "btrfs";
    options = ["subvol=/nixos-containers" "compress=zstd:3" "noatime" "flushoncommit" "nofail"];
  };

  fileSystems."/var/lib/libvirt" = {
    device = "bpool/trex/libvirt";
    fsType = "zfs";
    options = ["nofail"];
  };

  fileSystems."/mnt/victoriametrics" = {
    device = "/dev/disk/by-label/trexroot";
    fsType = "btrfs";
    options = ["subvol=/victoriametrics" "compress=zstd:3" "noatime" "flushoncommit" "nofail"];
  };

  # Do not let services fall through to the disposable tmpfs root if their
  # bpool datasets fail to mount.
  # Every bindMounts source in containers/arr-servers.nix must appear here.
  # nspawn resolves bind mounts once, at container start: if a source is not
  # mounted yet it binds whatever empty directory sits underneath, and the
  # container then runs happily against the wrong storage. /var/lib/jellyfin
  # and /var/lib/radarr|sonarr|autobrr are impermanence binds; /var/lib/
  # qbittorrent is ZFS; incomplete is the SPDK Optane volume.
  systemd.services."container@arr-servers".unitConfig.RequiresMountsFor = [
    "/var/lib/nixos-containers"
    "/var/lib/qbittorrent"
    "/var/lib/qbittorrent/incomplete"
    "/var/lib/jellyfin"
    "/mnt/Media"
  ];
  systemd.services.libvirtd.unitConfig.RequiresMountsFor = ["/var/lib/libvirt"];
  systemd.services.victoriametrics.unitConfig.RequiresMountsFor = [
    "/mnt/victoriametrics"
  ];

  # Explicit persistent state — everything else on / dies at reboot.
  # Dead tenants of the old root (lighthouse, reth, namada, bitcoind, ...)
  # are deliberately absent.
  environment.persistence."/persist".directories = [
    # infrastructure
    "/var/lib/acme"
    # Self-signed cert for the kimi vhost. Without this the impermanent root
    # discards it on every boot, so the fingerprint changes under the browser
    # each time; kimi-selfsigned-cert would regenerate it, but stability is
    # nicer. Added 2026-07-30 -- it was previously created by hand and not
    # persisted at all, which would have stopped nginx starting after a reboot.
    "/var/lib/kimi-certs"
    "/var/lib/samba"
    "/var/lib/nfs"
    {
      directory = "/var/lib/syncoid";
      user = "syncoid";
      group = "syncoid";
      mode = "0700";
    }
    "/var/lib/rasdaemon"
    "/var/lib/fwupd"
    "/var/lib/boltd"
    "/var/lib/krb5kdc"
    "/var/lib/docker"
    # Host-side state bind-mounted into the arr-servers container.
    "/var/lib/autobrr"
    "/var/lib/radarr"
    "/var/lib/sonarr"
    {
      directory = "/var/lib/grafana";
      user = "grafana";
      group = "grafana";
      mode = "0700";
    }
    {
      directory = "/var/lib/postgresql";
      user = "postgres";
      group = "postgres";
      mode = "0755";
    }
    # /var/lib/systemd/linger was here until 2026-08-09. It is declarative:
    # profiles/users.nix sets `linger = true` for grw and the users module
    # recreates the marker at activation, so persisting it was redundant.
    "/var/lib/OpenRGB"
    "/var/lib/qui"
    # services
    {
      directory = "/var/lib/jellyfin";
      user = "jellyfin";
      group = "jellyfin";
      mode = "0700";
    }
    # Exact live DynamicUser tenants. /var/lib/private itself must remain
    # disposable: persisting that parent would also retain dead lighthouse,
    # reth, llama-cpp, flood, and dnscrypt-proxy state forever.
    "/var/lib/private/hellas"
    "/var/lib/private/hellas-gateway"
    "/var/lib/private/open-webui"
    # Credentials for the root-owned gcp-ddns oneshot.
    {
      directory = "/root/.config/gcloud";
      mode = "0700";
    }
    # fleet logserver: journals + netconsole capture survive reboots
    {
      directory = "/var/log/journal";
      user = "root";
      group = "systemd-journal";
      mode = "2755";
    }
    "/var/log/netconsole"
  ];

  # systemd uses this host key to decrypt libvirt's encrypted credential.
  # Persist the one key, not the rest of /var/lib/systemd.
  environment.persistence."/persist".files = [
    "/var/lib/systemd/credential.secret"
  ];

  # Seed list mirrors the persistence list (normalized entries).
  sconfig.impermanence.seedExisting.directories =
    map (entry:
      if lib.isString entry
      then entry
      else entry.directory)
    config.environment.persistence."/persist".directories;
  sconfig.impermanence.seedExisting.files = [
    "/var/lib/systemd/credential.secret"
  ];

  # Override the impermanence default: this box is the fleet logserver.
  services.journald.storage = "persistent";
  services.journald.extraConfig = "SystemMaxUse=4G";

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/TREXBOOTA";
    fsType = "vfat";
    options = ["iocharset=iso8859-1" "fmask=0077" "dmask=0077"];
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
    device = "/dev/disk/by-label/nand4";
    fsType = "btrfs";
    options = ["subvol=/grw-home" "compress=zstd" "noatime" "nofail"];
  };

  # Bind mount for NFSv4 export
  fileSystems."/export/grw" = {
    device = "/home/grw";
    fsType = "none";
    options = ["bind"];
  };

  services = {
    fstrim.enable = true;
    fwupd.enable = true;
    hardware.openrgb.enable = true;
    iperf3.enable = true;

    # ZFS snapshot management - short retention on source
    sanoid = let
      excluded = {
        autosnap = false;
        hourly = 0;
        daily = 0;
        weekly = 0;
        monthly = 0;
      };
    in {
      enable = true;
      interval = "hourly";
      datasets."bpool/trex" = {
        recursive = true;
        autosnap = true;
        hourly = 24;
        daily = 7;
        weekly = 0;
        monthly = 0;
      };
      datasets."bpool/Home" = {
        autosnap = true;
        hourly = 24;
        daily = 7;
        weekly = 0;
        monthly = 0;
      };
      # Chain data: public, bulk, high-churn and fully re-downloadable, so it is
      # worth neither snapshots nor replication. monero, tari and p2pool moved
      # to btrfs subvolumes on nand4 on 2026-08-11 and these datasets were
      # destroyed on 2026-08-12; the entries stay as a guard in case a dataset
      # by one of these names is ever recreated. p2pool was the one that had
      # been missed, so it was snapshotted and replicated to fuckup for months.
      datasets."bpool/trex/tari" = excluded;
      datasets."bpool/trex/monero" = excluded;
      datasets."bpool/trex/p2pool" = excluded;
      # re-downloadable model weights — no snapshots (churn is large, value is zero)
      datasets."bpool/trex/models" = excluded;
      # Partial torrents are disposable and high-churn.
      datasets."bpool/trex/downloads/incomplete" = excluded;
    };

    # Replicate only current live datasets. --no-stream deliberately omits
    # pre-migration snapshot history, including partial torrent payloads that
    # predate the excluded downloads/incomplete child dataset.
    syncoid = let
      excludedDatasets = ["tari" "monero" "p2pool" "models" "bitcoind" "downloads/incomplete"];
      exclusions = lib.concatMap (d: ["--exclude-datasets" d]) excludedDatasets;
    in {
      enable = true;
      interval = "hourly";
      sshKey = "/var/lib/syncoid/.ssh/id_ed25519";
      commands."trex-bpool-to-archive" = {
        source = "bpool/trex";
        target = "root@fuckup:archive/pool3d/bpool-trex";
        recursive = true;
        sendOptions = "w";
        extraArgs = ["--no-stream"] ++ exclusions;
      };
      commands."home-to-archive" = {
        source = "bpool/Home";
        target = "root@fuckup:archive/pool3d/bpool-backup/Home";
        recursive = false;
        sendOptions = "w";
        extraArgs = ["--no-stream"];
      };
    };
  };

  networking = {
    hostName = "trex";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    nameservers = [network.routerIp];
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

  sops.secrets.nix-cache-key = mkSecret "nix-cache-key" {};

  systemd.network = let
    bridgeName = "br0.lan";
  in {
    enable = true;
    wait-online.anyInterface = true;
    links =
      {
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
      }
      // lib.mapAttrs'
      (name: mac:
        lib.nameValuePair "20-${name}" {
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
        address = ["169.254.0.18/16"];
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "ipv6";
          IPv6AcceptRA = false;
        };
        linkConfig.RequiredForOnline = "no";
      };

      # The 100G PF carries trex's addresses directly (2026-08-08). Previously
      # these lived on the OVS internal port ovs-host, which forced RDMA onto a
      # separate VF; on a real netdev the verbs device comes for free and RoCE
      # runs natively. The lan and fabric subnets deliberately share this one
      # L2 domain, as they did on ovs-host.
      #
      # 192.168.25.208 is the RDMA endpoint (network.hosts."trex-rdma"). It is
      # kept as a distinct address so every client's NVMe-oF target address is
      # unchanged by this rework -- important because the strix nodes netboot
      # from this host and cannot be updated in lockstep.
      "10-lan-100g" = {
        matchConfig.Name = mlxPfName;
        address = [
          (network.cidrOf "lan" self.addresses.lan)
          (network.cidrOf "fabric" self.addresses.fabric)
          (network.cidrOf "fabric" network.hosts."trex-rdma".addresses.fabric)
        ];
        routes = [
          {Gateway = network.routerIp;}
          # The management daemon is on the BlueField itself. Its fabric
          # address is now directly connected; only the private DPU address
          # still needs the BlueField LAN side as a gateway.
          {
            Destination = "192.168.100.2/32";
            Gateway = bluefield2LanIp;
          }
        ];
        networkConfig = {
          DNS = network.routerIp;
          MulticastDNS = "yes";
        };
        # Only autoconfigure SLAAC from our ISP's delegated /64. Rogue RAs from
        # other devices on the LAN (e.g. Apple devices acting as Tailscale
        # subnet routers) advertise ULA prefixes that briefly get autoconfigured
        # and then trigger ICMPv6 "advertised our address" dmesg spam.
        ipv6AcceptRAConfig = {
          PrefixAllowList = "2a02:168:58b4::/64";
        };
        linkConfig = {
          ActivationPolicy = "up";
          RequiredForOnline = "routable";
          MTUBytes = "9000";
        };
      };

      # 10G Intel ports: plain DHCP clients, not bridged to anything. Both are
      # unplugged today (carrier=0, zero bytes); they used to be OVS ports for
      # no reason anyone could name.
      "30-i40e" = {
        matchConfig.Name = "i40e*";
        networkConfig.DHCP = "yes";
        linkConfig.RequiredForOnline = "no";
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
        bridgeConfig = {};
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
    # Individual DynamicUser subtrees are persisted, not their parent. Keep the
    # source-side parent private without turning it into a persistence catch-all.
    "d /persist/var/lib/private 0700 root root -"
    # qBittorrent profile + separately mounted incomplete dataset
    "d /var/lib/qbittorrent 0775 qbittorrent qbittorrent -"
    "d /var/lib/qbittorrent/incomplete 0775 qbittorrent qbittorrent -"
  ];
}
