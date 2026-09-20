index: { pkgs
       , lib
       , inputs
       , mkSecret
       , config
       , network
       , ...
       }:
let
  hostName = "strix-${toString index}";
  self = network.hosts.${hostName};
  # Diskless hosts boot via PXE/iPXE and seed a fresh private SPDK store. The
  # flag lives in network.nix so the router (DHCP/TFTP) and trex
  # (exports/boot files) stay in sync with the machine config.
  netboot = self.netboot or false;
  # Per-host hardware facts (CX5 port ownership, power limits) live in the
  # network.nix host record — the single inventory.
  # Temporarily disable the custom Thunderbolt kernels and RDMA module.
  # To restore them, use `builtins.elem index [ 1 2 3 ]`.
  enableUsb4Rdma = false;
  enableCx5Fabric = builtins.elem index [ 1 2 3 4 ];
  enableSharedCx5 = enableCx5Fabric;
  netbootSharesFabric = netboot && (self.netbootSharesFabric or false);
  trainPrimaryInInitrd = netboot && (self.strix.forcePrimaryFabricLink or false);

  # The shared ConnectX-5 ports attach to the Ethernet-only CRS804.  Keep the
  # separate flag so the old IPoIB/OpenSM experiment cannot silently return.
  enableSharedIb = false;
  enableUsb4Tcp = false;
  reserveThunderbolt0ForMac = false;
  ryzenAdjLimits = self.strix.ryzenAdj;

  # The 120 W strix-3/4 boards give substantially more decode throughput when
  # CPU boost cannot consume the GPU's package-power headroom.
  inferenceCpuMaxKHz = if builtins.elem index [ 3 4 ] then 2500000 else null;
  cx5ForcedSpeed = if self.strix.bluefield or false then "100G_4X" else "100G";
  tbvPackages = inputs.thunderbolt-ibverbs-kernel.packages.${pkgs.stdenv.hostPlatform.system} or { };
  tbvHipGdaProbes = tbvPackages."tbv-hip-gda-probes" or null;
  hellasVideoPackages =
    inputs.hellas-ai-video.packages.${pkgs.stdenv.hostPlatform.system};
  h3V620Cli = pkgs.symlinkJoin {
    name = "hellas-minimax-h3-v620-cli";
    paths = map
      (command: pkgs.writeShellScriptBin "${command}-v620" ''
        exec ${hellasVideoPackages.h3-rocm-v620}/bin/${command} "$@"
      '')
      [ "h3-generate" "h3-condition" "h3-denoise" "h3-doctor" ];
  };

  # trex's models export. The constants file is the single pin shared by the
  # target and every client; see machines/x86/trex/spdk-storage-constants.nix.
  modelsStorage = import ../trex/spdk-storage-constants.nix;
  modelsDevice = "/dev/disk/by-id/nvme-uuid.${modelsStorage.modelsSnapshot.uuid}";
  modelsTargetAddress =
    network.ipOf "fabric" network.hosts."trex-rdma".addresses.fabric;
  # Deterministic per-host NVMe host ID in UUID form. hashString gives 64 hex
  # characters; the first 32 are sliced into the 8-4-4-4-12 layout.
  nvmeHostIdHash = builtins.hashString "sha256" "nvme-hostid-${hostName}";
  nvmeHostId = lib.concatStringsSep "-" [
    (lib.substring 0 8 nvmeHostIdHash)
    (lib.substring 8 4 nvmeHostIdHash)
    (lib.substring 12 4 nvmeHostIdHash)
    (lib.substring 16 4 nvmeHostIdHash)
    (lib.substring 20 12 nvmeHostIdHash)
  ];

  vllmFabricInterface = "cx5fabric0";
  vllmFabric2Interface = "cx5fabric1";
  # Require both inventory fields so this shared module only creates the
  # second CX5 rail on hosts whose permanent MAC and address are explicit.
  enableCx5Fabric2 = enableCx5Fabric
    && self.strix ? cx5Fabric2Mac
    && self.addresses ? fabric2;
  # Resolve the intended PF by its permanent MAC before forcing its link.  The
  # numeric mlx5 name is not stable across PCI enumeration, especially on the
  # two-card hosts.  One target per service keeps the netboot exception for the
  # primary/NFS rail from accidentally applying to the independent second rail.
  cx5FabricLinkScript = targetMac: ''
    target_mac=${lib.escapeShellArg targetMac}
    nic_path=
    for _ in $(${pkgs.coreutils}/bin/seq 1 30); do
      for candidate in /sys/class/net/*; do
        [ -r "$candidate/address" ] || continue
        if [ "$(${pkgs.coreutils}/bin/cat "$candidate/address")" = "$target_mac" ]; then
          nic_path="$candidate"
          break 2
        fi
      done
      ${pkgs.coreutils}/bin/sleep 1
    done

    if [ -z "$nic_path" ]; then
      echo "fabric NIC with permanent MAC $target_mac did not appear" >&2
      exit 1
    fi

    pci_path=$(${pkgs.coreutils}/bin/readlink -f "$nic_path/device")
    pci_address="''${pci_path##*/}"
    exec ${pkgs.mlnx-mft}/bin/mlxlink \
      -d "$pci_address" \
      -s ${cx5ForcedSpeed} \
      --link_mode_force \
      --yes
  '';
  vllmHostIp =
    if enableCx5Fabric
    then network.ipOf "fabric" self.addresses.fabric
    else "10.5.0.${toString index}";
  # The NVMe-oF paths the connector must establish. A list of one today.
  #
  # A second path over the node's other ConnectX-5 was built on 2026-08-08 and
  # then withdrawn: measurement showed the fabric delivers 28.2 Gb/s over TCP
  # but only ~7.7 Gb/s over raw RDMA on the identical path, so RoCE is running
  # at a quarter of what the wire and PCIe allow. Doubling the paths would
  # double nothing until that is understood. The machinery below stays because
  # it is strictly better than what it replaced -- it tracks each path by
  # (traddr, host_traddr) rather than by "is this NQN connected at all", which
  # is what a second path would silently trip over -- and because it makes
  # adding the second rail a one-entry change once RoCE is fixed.
  modelsPaths = lib.optionals enableCx5Fabric [{
    interface = vllmFabricInterface;
    hostIp = vllmHostIp;
    target = modelsTargetAddress;
  }];

  linuxPackagesStrix =
    (if enableUsb4Rdma
     then pkgs.linuxPackagesFor tbvPackages.linux-thunderbolt
     else pkgs.linuxPackages_latest).extend (_: super: {
      ryzen-smu = super.ryzen-smu.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ lib.optionals
          (lib.versionAtLeast super.kernel.version "7.2")
          [ ../../../profiles/patches/ryzen-smu-linux-7.2-cpuid-header.patch ];
      });
    });
in
{
  /*
    FEVM Strix Halo
  */
  users.groups.video.members = map (n: "nixbld${toString n}") (lib.range 1 32);
  users.groups.render.members = map (n: "nixbld${toString n}") (lib.range 1 32);

  sconfig = {
    profile = "server";
    # Host half of the CRS804's lossless RoCE policy (modules/roce-qos.nix).
    roceQos = lib.mkIf enableCx5Fabric {
      enable = true;
      interface = vllmFabricInterface;
      extraInterfaces = lib.optionals enableCx5Fabric2 [ vllmFabric2Interface ];
      # Follow resets in this boot stage. The netboot primary is trained in
      # the initrd; tying stage-2 QoS to that unit would propagate its stop
      # across switch-root.
      afterUnits = lib.optionals (!trainPrimaryInInitrd) [
        "cx5-fabric-link.service"
      ] ++ lib.optionals enableCx5Fabric2 [ "cx5-fabric2-link.service" ];
    };
    home-manager = {
      enable = true;
      enableDevelopment = true;
    };
    xmrig = {
      enable = true;
      package = pkgs.xmrig-zen5;
    };
  };

  system.stateVersion = "24.11";

  hardware.amdgpu.v620PowerCap = lib.mkIf (self.strix ? v620) {
    enable = true;
    watts = self.strix.v620.powerLimitWatts;
    expectedCount = self.strix.v620.count;
  };

  # Large local and distributed checkpoint loads can hold a CPU in kernel I/O
  # long enough to miss the fleet-wide 15 s watchdog deadline. Strix-3 first
  # exposed this under DSV4; H3 reproduced the same reset class on strix-2.
  systemd.settings.Manager = {
    RuntimeWatchdogSec = lib.mkForce "60s";
  };

  hardware.cpu.amd.ryzen-smu.enable = true;
  programs.ryzen-monitor-ng.enable = true;

  # Export the APU's versioned SMU table, every AMD GPU's sysfs telemetry, and
  # the NPU into node_exporter's shared textfile collector.
  services.strix-halo.smu-exporter.enable = true;
  services.strix-halo.npu-exporter.enable = true;

  environment.systemPackages = [
    pkgs.kexec-tools
    pkgs.mlnx-mft
    pkgs.perftest
    pkgs.iperf3
    pkgs.mlnx-opensm
    pkgs.pciutils
    # Inspect named IFR questions or exact, experimentally-confirmed EFI
    # variable offsets from the running host. Raw writes require an expected
    # current value and keep full-variable backups before changing NVRAM.
    pkgs.bios-setup-var
    # Every Strix APU can run H3's gfx1151 conditioning/full-offload path.
    # Referencing it here also roots the closure in trex's served netboot
    # image, avoiding the clients' deliberately tiny writable Nix stores.
    hellasVideoPackages.h3-rocm
    # One gfx1151 rank per host; FSDP/Ulysses spans all four over cx5fabric0.
    # The V620-local profiles below remain separate and available on strix-3.
    hellasVideoPackages.h3-sglang-rocm
    # Root the RDMA-enabled Hellas runner bundle in every served image. This
    # carries xDiT/Ulysses, torchrun, the collective smoke benchmark, and LTX
    # DistVAE with the USB4-aware userspace provider; clients cannot safely
    # build this closure in their small writable netboot stores.
    hellasVideoPackages.distributed-rocm-rdma
    # Music 3 fits on the gfx1151 APU and shares the same pinned Diffusers /
    # Transformers runtime as H3. Root it on all four nodes so independent
    # songs (or pipeline jobs) can be scheduled without client-side builds.
    hellasVideoPackages.music3-rocm
  ] ++ lib.optionals enableCx5Fabric [
    pkgs.nvme-cli
  ] ++ lib.optionals (index == 3) [
    # strix-3 is the designated four-V620 host. Keep the gfx1030 closures in
    # its netboot image while those cards are temporarily out for cooling and
    # service; the hybrid launcher keeps both architectures in separate
    # interpreters and hands pipeline state across the process boundary.
    h3V620Cli
    hellasVideoPackages.h3-hybrid-rocm
    hellasVideoPackages.music3-rocm-v620
    # Native SGLang 0.5.17 supplies the experimental four-card FSDP/Ulysses
    # and TP4 paths. Seed it with the system so serving needs no download.
    hellasVideoPackages.h3-sglang-rocm-v620
  ];

  environment.etc."mft/mft.conf" = lib.mkIf enableSharedCx5 {
    source = "${pkgs.mlnx-mft}/etc/mft/mft.conf";
  };

  boot.loader.systemd-boot.configurationLimit = lib.mkForce 4;
  boot.kernelPackages = lib.mkOverride 900 linuxPackagesStrix;

  # Keep resource transfer manual for the first hardware qualification. APIC
  # IDs 24-31 are both SMT threads of physical cores 12-15 on strix-4.
  boot.multikernel = lib.mkIf (index == 4) {
    # Temporarily use the stock kernel during the fleet upgrade.
    enable = false;
    pool = {
      cpus = "24-31";
      memory = "8GB";
      prepareAtBoot = false;
    };
    instances = {
      blue = {
        id = 1;
        cpus = "24-27";
        memory = "2GB";
      };
      red = {
        id = 2;
        cpus = "28-31";
        memory = "2GB";
      };
    };
  };

  boot.kernelParams =
    [
      "iommu=pt"
      # Permit privileged firmware tooling to map the system ROM through
      # /dev/mem. This is intentionally shared by all four lab nodes so a
      # socketed BIOS can be captured and verified from Linux.
      "iomem=relaxed"
    ]
    # Netboot hosts skip profiles/uefi-boot.nix, which normally supplies
    # these host-class tuning params.
    ++ lib.optionals netboot [
      "msr.allow_writes=on"
      "mitigations=off"
    ]
    # The PEX880xx subtree on strix-4 needed one more 1 MiB bridge window than
    # firmware allocated on the 2026-07-24 cold boot. Without reallocation the
    # NVMe link trained, but BAR 0 remained unassigned and nvme_probe returned
    # -ENODEV.
    ++ lib.optionals (netboot && index == 4) [
      "pci=realloc=on"
    ]
    # On a cold boot Strix-2's firmware assigns the complete PEX88096 bus tree
    # and all four 32 GiB V620 PF BARs correctly. Do not add pci=assign-busses:
    # on this switch it clears the hardware bridge bus-number registers while
    # leaving Linux's cached tree populated, so every endpoint reads as ffff.
    # Do not add pci=realloc either: it releases the valid PF BARs while trying
    # unsuccessfully to fit each card's unused 384 GiB SR-IOV VF aperture.
    # Disabled after strix-1 amdgpu failed to fetch VBIOS from ACPI VFCT while
    # booted with these experimental PCIe enumeration parameters.
    ++ lib.optionals false [
      "pci=realloc,assign-busses"
      "pcie_ports=native"
    ];

  # Strix-2 firmware Setup must keep PCI Hot-Plug -> PCI Buses Padding at 5.
  # The old value 1 only reserved buses 03-06 after a genuine PEX-board cold
  # start; value 5 was cold-boot verified to reserve the complete 03-22 tree.
  # A warm reboot does not reset the PEX88096 board, and firmware can leave its
  # bridge bus-number registers cleared on the next hand-off.  When Linux has
  # already discovered the complete topology, put the exact retained hierarchy
  # back before udev or the explicit initrd module list can bind amdgpu/mlx5_core.
  boot.initrd.systemd.storePaths = lib.optionals (netboot && index == 2) [
    "${pkgs.pciutils}/bin/setpci"
  ] ++ lib.optionals trainPrimaryInInitrd [
    pkgs.mlnx-mft
  ];
  boot.initrd.systemd.contents."/etc/mft/mft.conf" =
    lib.mkIf trainPrimaryInInitrd {
      source = config.environment.etc."mft/mft.conf".source;
    };
  boot.initrd.systemd.services.strix2-pex-bus-restore = lib.mkIf (netboot && index == 2) {
    description = "Restore Strix-2 PEX88096 bridge routing";
    wantedBy = ["initrd.target"];
    before = [
      "systemd-modules-load.service"
      "systemd-udev-trigger.service"
    ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      setpci=${pkgs.pciutils}/bin/setpci

      # Restoring 03-22 is safe only when firmware/Linux already reserved that
      # complete range for GPP5.  If the firmware setting is lost, a genuine
      # PEX-board power cycle reserves only 03-06 and assigns 07 onward to other
      # root ports; expanding the switch in that layout would alias the CX5,
      # iGPU, NPU, and USB4 buses.  In that case leave the machine usable and
      # report the insufficient reservation instead.
      root_buses="$($setpci -s 00:02.5 18.L 2>/dev/null || true)"
      if [ "$root_buses" != 00220300 ]; then
        echo "PEX root port has buses $root_buses, not reserved 03-22; skipping unsafe restore"
        exit 0
      fi

      cached_endpoint() {
        endpoint="$1"
        expected_vendor="$2"
        vendor_path="/sys/bus/pci/devices/0000:$endpoint/vendor"
        [ -r "$vendor_path" ] || return 1
        IFS= read -r cached_vendor < "$vendor_path"
        [ "$cached_vendor" = "$expected_vendor" ]
      }

      if ! cached_endpoint 0a:00.0 0x15b3 \
        || ! cached_endpoint 0f:00.0 0x1002 \
        || ! cached_endpoint 12:00.0 0x1002 \
        || ! cached_endpoint 17:00.0 0x1002 \
        || ! cached_endpoint 1d:00.0 0x1002; then
        echo "complete cached V620/BlueField topology is absent; skipping bus restore"
        exit 0
      fi

      # The root port itself remains configured and makes 03:00.0 reachable;
      # each restored parent then exposes the next level of the hierarchy.
      if [ "$($setpci -s 03:00.0 0.W 2>/dev/null || true)" != 1000 ]; then
        echo "PEX88096 upstream bridge is absent; skipping bus restore"
        exit 0
      fi

      restore_bridge() {
        pex_bdf="$1"
        pex_buses="$2"
        $setpci -s "$pex_bdf" 18.L="$pex_buses"
        $setpci -s "$pex_bdf" COMMAND=0007
      }

      restore_bridge 03:00.0 00220403
      restore_bridge 04:00.0 000a0504
      restore_bridge 04:04.0 00120b04
      restore_bridge 04:08.0 001d1304
      restore_bridge 04:0c.0 00211e04
      restore_bridge 04:1c.0 00222204
      restore_bridge 05:00.0 000a0605
      restore_bridge 06:04.0 00070706
      restore_bridge 06:08.0 00080806
      restore_bridge 06:0c.0 00090906
      restore_bridge 06:10.0 000a0a06
      restore_bridge 0b:00.0 00120c0b
      restore_bridge 0c:00.0 000f0d0c
      restore_bridge 0c:10.0 0012100c
      restore_bridge 0d:00.0 000f0e0d
      restore_bridge 0e:00.0 000f0f0e
      restore_bridge 10:00.0 00121110
      restore_bridge 11:00.0 00121211
      restore_bridge 13:00.0 001d1413
      restore_bridge 14:00.0 00171514
      restore_bridge 14:04.0 00181814
      restore_bridge 14:08.0 00191914
      restore_bridge 14:0c.0 001a1a14
      restore_bridge 14:10.0 001d1b14
      restore_bridge 15:00.0 00171615
      restore_bridge 16:00.0 00171716
      restore_bridge 1b:00.0 001d1c1b
      restore_bridge 1c:00.0 001d1d1c
      restore_bridge 1e:00.0 00211f1e
      restore_bridge 1f:14.0 0020201f
      restore_bridge 1f:15.0 0021211f

      for endpoint in 0a:00.0 0f:00.0 12:00.0 17:00.0 1d:00.0; do
        vendor="$($setpci -s "$endpoint" 0.W 2>/dev/null || true)"
        if [ "$vendor" = ffff ] || [ -z "$vendor" ]; then
          echo "PEX endpoint $endpoint is still inaccessible after bus restore" >&2
          exit 1
        fi
      done
    '';
  };

  deployment.targetHost = network.primaryIp self;
  deployment.targetUser = "grw";

  sops.secrets.mosquitto-password = mkSecret "mosquitto-password" {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  hardware.strixHalo = {
    enable = true;
    # Efficient-but-boostable: DPM idles the GPU clocks (sclk rests ~600 MHz)
    # and still reaches peak under load, instead of pinning sclk at max. On an
    # idle box this measured ~14 W -> ~10 W socket, with full boost preserved.
    amdgpuDpmState = "balanced";
    amdgpuPerformanceLevel = "auto";
    # amd_pstate guided + schedutil: dynamic, scheduler-driven scaling that
    # still reaches full boost, without active mode's misleading "powersave"
    # governor. Measured ~14 W -> ~7 W idle socket on a spare box, boost still
    # ~5 GHz. Idle cores drop below the old 2 GHz floor; boxes 3/4 keep their
    # inference scaling_max_freq cap (applied after this).
    cpuPower = {
      amdPstateMode = "guided";
      governor = "schedutil";
      minToHardwareFloor = true;
    };
  };

  # Each node has its OWN ConnectX-5; they do not share one. Verified
  # 2026-07-30 with mstflint: strix-1's card is base GUID 1c34da0300611298 and
  # strix-2's is 1c34da03006112b0 -- different cards, both the SharedIO
  # "Adapter Kit" SKU (PSID LNV0000000012), i.e. a two-card kit joined by an
  # interlink cable, which has been disconnected.
  #
  # The multi-host/Socket-Direct functions are also already disabled in
  # firmware on both: HOST_CHAINING_MODE=DISABLED, MULTI_PORT_VHCA_EN=False,
  # PF_SD_GROUP=0. So forcing one node's link cannot disturb another's, and
  # there is nothing left to turn off. Do NOT "disable" PORT_OWNER looking for
  # a multi-host switch: True means this host owns its own physical port, and
  # clearing it surrenders port control.
  #
  # Ports connect to the CRS804 Ethernet fabric; hardware.infiniband supplies
  # the verbs/RDMA userspace.
  hardware.infiniband = {
    enable = enableCx5Fabric;
  };

  # RouterOS 7.23.2 and the HELLAS HQSFP56-200G-C1M DACs fail 100G
  # autonegotiation. Match the CRS804's forced 100G CR4 configuration after
  # every boot or PCI reset. Select each cabled PF by inventory MAC: numeric
  # mlx5 names are PCI-enumeration accidents, and unused functions are visible.
  # Netboot hosts train in the initrd when requested by inventory, before
  # their private store starts using the fabric. Local boots train in stage 2.
  systemd.services.cx5-fabric-link =
    lib.mkIf (enableCx5Fabric && !netboot) {
    description = "Force the primary CRS804 fabric link to 100 GbE";
    wants = lib.optionals (self.strix.bluefield or false) [ "bluefield-nic-bind.service" ];
    wantedBy = [ "network-online.target" ];
    before = [ "network-online.target" ];
    after = [ "systemd-udevd.service" ]
      ++ lib.optionals (self.strix.bluefield or false) [ "bluefield-nic-bind.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = cx5FabricLinkScript self.strix.cx5FabricMac;
  };

  # Train the independent fabric port before connecting the netboot store.
  # Repeating this in stage 2 would reset the link underneath /nix.
  boot.initrd.systemd.services.cx5-fabric-link =
    lib.mkIf trainPrimaryInInitrd {
      description = "Force the primary CRS804 fabric link to 100 GbE";
      wantedBy = [ "network-online.target" ];
      before = [ "network-online.target" ];
      after = [ "systemd-udev-trigger.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = cx5FabricLinkScript self.strix.cx5FabricMac;
    };
  # Rail 2 is independent of the primary/NFS rail, so it must not inherit the
  # primary service's !netboot exclusion.  It has its own exact MAC selector
  # and unit, so strix-2's local boot never double-runs the secondary PF and
  # strix-3 (which has no secondary inventory/address) emits no unit at all.
  systemd.services.cx5-fabric2-link = lib.mkIf enableCx5Fabric2 {
    description = "Force the secondary CRS804 fabric link to 100 GbE";
    wants = lib.optionals (self.strix.bluefield or false) [ "bluefield-nic-bind.service" ];
    wantedBy = [ "network-online.target" ];
    before = [ "network-online.target" ];
    after = [ "systemd-udevd.service" ]
      ++ lib.optionals (self.strix.bluefield or false) [ "bluefield-nic-bind.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = cx5FabricLinkScript self.strix.cx5Fabric2Mac;
  };

  # Clear PCIe ACS P2P-redirect on the Broadcom PEX880xx switch bridges so
  # GPUDirect P2P (V620 VRAM <-> BlueField ConnectX-6, both under the switch)
  # stays in-switch at x16 rather than being redirected up the x4 host uplink.
  # Keyed on the switch vendor:device (1000:c010) because bridge BDFs renumber
  # across reboots. Safe under iommu=pt on this dedicated compute host: the ACS
  # control register keeps SrcValid (0x0001) and drops only the redirect bits.
  # Unconditional: no-op on hosts without the switch, and the DPU/PEX board
  # moves between chassis — keying this on the bluefield inventory flag
  # silently dropped the clear everywhere when the card moved out of strix-3
  # (2026-07-29 GPU attach + thermal incident).
  systemd.services.pex-acs-clear = {
    description = "Clear ACS P2P redirect on the PEX880xx GPU/NIC fabric switch";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      cleared=0
      for dev in /sys/bus/pci/devices/*; do
        [ "$(${pkgs.coreutils}/bin/cat "$dev/vendor" 2>/dev/null)" = "0x1000" ] || continue
        [ "$(${pkgs.coreutils}/bin/cat "$dev/device" 2>/dev/null)" = "0xc010" ] || continue
        bdf=$(${pkgs.coreutils}/bin/basename "$dev")
        bdf=''${bdf#0000:}
        if ${pkgs.pciutils}/bin/setpci -s "$bdf" ECAP_ACS+0x6.w=0001 2>/dev/null; then
          cleared=$((cleared + 1))
        fi
      done
      echo "pex-acs-clear: cleared ACS on $cleared PEX880xx bridges"
    '';
  };

  # Strix Halo GPU workloads use UMA heavily. Large vLLM runs can leave
  # little "available" RAM while still being healthy, so earlyoom kills the
  # benchmark runner or EngineCore before the kernel OOM killer would act.
  services.earlyoom.enable = lib.mkForce false;

  # One uniform layout replaces the old single-disk/RAID0 split. Disko does
  # not run during nixos-rebuild: it only makes the destructive provisioning
  # operation explicit and repeatable when invoked deliberately.
  #
  # Locally-booting nodes own their disk: the root and ESP partitions provisioned
  # by disko. mkForce overrides the device references the netboot profile would
  # otherwise supply. Netboot nodes use a tmpfs root and a fresh SPDK store.
  fileSystems."/" = lib.mkIf (!netboot) (lib.mkForce {
    device = "/dev/disk/by-partlabel/${hostName}-root";
    fsType = "btrfs";
    options = [ "subvol=@root" "compress=zstd:1" "discard=async" "noatime" ];
    neededForBoot = true;
  });
  fileSystems."/boot" = lib.mkIf (!netboot) (lib.mkForce {
    device = "/dev/disk/by-partlabel/${hostName}-ESP";
    fsType = "vfat";
    options = [ "umask=0077" ];
  });

  imports = (with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd
    common-gpu-amd
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/headless.nix
    ../../../profiles/radeon.nix

    ../../../services/buildfarm-executor.nix
    ../../../profiles/nas-mounts.nix
    ../../../services/buildfarm-slave.nix
    ../../../services/hydra-builder-slave.nix

    ../../../profiles/thunderbolt-bridge.nix

    # Bench SMBus master for the PEX880xx boards' SMBUS header, over a CH341A
    # USB dongle. Inert with nothing plugged in; see the profile for why it is
    # not keyed on a per-host flag.
    ../../../profiles/ch341-i2c.nix

    inputs.disko.nixosModules.disko
    ../../../profiles/nix-strix-halo.nix
    inputs.nix-strix-halo.nixosModules.benchmark-runner
    inputs.nix-strix-halo.nixosModules.rpc-server
    inputs.nix-strix-halo.nixosModules.fastflowlm
    inputs.nix-strix-halo.nixosModules.ec-su-axb35
    inputs.nix-strix-halo.nixosModules.ryzenadj
    inputs.nix-strix-halo.nixosModules.amduprof
    inputs.nix-strix-halo.nixosModules.smu-exporter
    inputs.nix-strix-halo.nixosModules.npu-exporter
    (inputs.nix-strix-halo-multikernel + "/modules/multikernel.nix")

    ../../../profiles/amd-npu.nix
    ../../../profiles/amd-v620-powercap.nix
  ]) ++ [
    ./hellas.nix
    (import ./ds4-serve.nix index)
    (import ./qwen38-v620-serve.nix index)
    (if netboot
    then ../../../profiles/netboot-client.nix
    else ../../../profiles/uefi-boot.nix)
  ] ++ lib.optionals enableUsb4Rdma [
    ../../../profiles/thunderbolt-ibverbs-kernel.nix
  ] ++ lib.optional (self.strix.bluefield or false) (
    ../../../profiles/bluefield-host.nix
  );

  hardware.graphics = {
    enable = true;
    enable32Bit = lib.mkForce false;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
    ];
  };

  services.ec-su-axb35 =
    {
      enable = true;
      monitor.enable = true;
      powerMode = "performance";
    };

  # Writing the EC power mode restores the board's stock SMU limits. Apply
  # RyzenAdj afterwards so the configured package limits win deterministically.
  systemd.services.ryzenadj.after = [ "ec-su-axb35-config.service" ];

  services.ryzenadj = {
    enable = true;
    stapmLimit = ryzenAdjLimits.stapm;
    fastLimit = ryzenAdjLimits.fast;
    slowLimit = ryzenAdjLimits.slow;
    # UINT32_MAX is RyzenAdj's "not supplied" sentinel, so this is the
    # largest time constant its CLI can actually send to the SMU.
    stapmTime = 4294967294;
    apuSlowLimit = ryzenAdjLimits.apuSlow;
    maxPerformance = true;
    # Strix Halo clips tctl above 98 C. Setting this also raises the visible
    # STT APU/dGPU limits; direct apuSkinTemp/dgpuSkinTemp writes are not
    # supported by ryzenadj on this family.
    tctlTemp = 98;
    # Keep Curve Optimizer neutral while validating long-running inference.
    # Aggressive all-core undervolts can fail only under sustained decode load.
    curveOptimizer = {
      enable = true;
      offset = 0;
      graceSeconds = 0;
    };
  };

  systemd.services.strix-halo-inference-cpu-cap = lib.mkIf (inferenceCpuMaxKHz != null) {
    description = "Reserve Strix Halo package power for sustained GPU inference";
    after = [ "systemd-modules-load.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for attempt in $(${pkgs.coreutils}/bin/seq 1 20); do
        found=0
        for limit in /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq; do
          [ -e "$limit" ] || continue
          found=1
          echo ${toString inferenceCpuMaxKHz} > "$limit"
        done
        if [ "$found" -eq 1 ]; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 0.5
      done
      echo "CPU frequency policies did not appear" >&2
      exit 1
    '';
  };

  services.curve-optimizer = {
    enable = true;
    # -10 survived both sustained TP4 decode and the loaded-to-idle edge on
    # all four hosts. Keep it opt-in; stronger per-host values need soak tests.
    offset = -10;
    mqtt = {
      enable = true;
      host = network.controlPlaneIp;
      username = "rw";
      passwordFile = config.sops.secrets.mosquitto-password.path;
    };
  };

  systemd.services.curve-optimizer-mqtt = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
  };

  programs.amduprof = {
    enable = true;
    powerProfiling.enable = true;
  };

  nix.settings = {
    system-features = [
      "gccarch-znver5"
      "rocm"
      "gfx1151"
      "aimax395"
      "kvm"
      "nixos-test"
      "big-parallel"
    ];

    # FastFlowLM bench derivations talk to the NPU via XRT, which opens
    # /dev/accel/accel0 (amdxdna DRM accel device) and walks sysfs to
    # enumerate devices (xrt::device(0) needs PCI topology to find the
    # NPU, which lives under /sys/devices and /sys/bus/pci). ROCm's libdrm
    # path also needs /sys/dev/char to classify render nodes correctly.
    # Models are pre-staged at /models/flm/ by `flm pull` with
    # FLM_MODEL_PATH set.
    extra-sandbox-paths = [
      "/dev/dri"
      "/dev/kfd"
      "/dev/shm"
      "/dev/accel"
      "/sys/class/drm"
      "/sys/class/kfd"
      "/sys/class/accel"
      "/sys/bus/pci"
      "/sys/devices"
      "/sys/dev"
      "/proc"

      # and the pinned NVMe/RDMA models snapshot
      "/models"
    ];
  };

  benchmark.runners.strix-halo = {
    requireIommuOff = false;
    gpus = [
      {
        type = "amd";
        arch = "1151";
      }
    ];
    npus = [
      {
        type = "amd";
        arch = "xdna2";
      }
    ];
    systemFeatures = [
      "gccarch-znver5"
      "rocm"
      "aimax395"
      "kvm"
      "nixos-test"
      "big-parallel"
    ];
  };

  # FastFlowLM pins NPU input/output buffers with mlock; on the default
  # 8 MB nixbld limit it warns and falls back to pageable memory, which
  # bench numbers depend on avoiding. nix-daemon spawns builders so the
  # limit must be set on the daemon's systemd unit.
  systemd.services.nix-daemon.serviceConfig.LimitMEMLOCK = "infinity";

  # ROCm build-time JIT derivations run in Nix's sandbox without the
  # caller's supplemental groups. Some ROCm imports still touch the primary
  # DRM node before settling on the render node, so expose it like the NPU
  # accel device below.
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ATTRS{vendor}=="0x1002", MODE="0666"
  '';

  # NPU server. The fastflowlm module installs a MODE=0666 udev
  # rule on /dev/accel/accel0 so the service and the bench-flm-*
  # nixbld builders both have access without per-user group plumbing.
  services.fastflowlm = {
    enable = false;
    # IOMMU passthrough is an explicit host policy in boot.kernelParams; do not
    # make that policy depend on whether this NPU service is enabled.
    setIommuPt = false;
    model = "gpt-oss:20b";
    openFirewall = false;
  };

  services = {
    fstrim.enable = true;
    fwupd.enable = true;
    iperf3 = {
      enable = true;
      openFirewall = true;
    };
  };

  # trex's pinned read-only models snapshot over NVMe-oF/RDMA, bound explicitly
  # to ${vllmFabricInterface}. RDMA needs a verbs device, so this can never
  # silently fall back to the 2.5G Realtek — if the fabric address is not on the
  # ConnectX, the connection simply does not happen.
  fileSystems."/models" = lib.mkIf enableCx5Fabric {
    device = modelsDevice;
    fsType = "xfs";
    options = [
      "ro"
      # A frozen XFS snapshot is consistent, but XFS still considers its log to
      # need recovery on a different host. The lvol snapshot rejects those
      # writes, so mount without replaying it.
      "norecovery"
      "nofail"
      "_netdev"
      "x-systemd.requires=nvme-trex-models.service"
      "x-systemd.after=nvme-trex-models.service"
      "x-systemd.device-timeout=30s"
    ];
  };

  # Every client of one target needs its own host NQN, or the target treats them
  # as multiple paths from a single host. Derived from the hostname so it is
  # stable across reboots — these roots are diskless, so /etc/machine-id cannot
  # be relied on to persist.
  environment.etc."nvme/hostnqn" = lib.mkIf enableCx5Fabric {
    text = "nqn.2026-07.link.satanic:${hostName}\n";
  };
  environment.etc."nvme/hostid" = lib.mkIf enableCx5Fabric {
    text = "${nvmeHostId}\n";
  };

  systemd.services.nvme-trex-models = lib.mkIf enableCx5Fabric {
    description = "Connect trex's pinned read-only models snapshot over NVMe/RDMA";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.iproute2
      pkgs.kmod
      pkgs.nvme-cli
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # Must never be fatal: a missing fabric leaves /models absent, which is bad,
    # but a failing unit that blocked the boot of a diskless node would be worse.
    unitConfig.StartLimitIntervalSec = 0;
    script = ''
      set -euo pipefail

      modprobe nvme-rdma

      # Multipath, not failover. Each path rides a different ConnectX-5 on its
      # own PCIe Gen3 x4 root port, so together they lift the ceiling from
      # ~3.5 GB/s to ~7 GB/s. Both controllers share a subsystem NQN and
      # namespace UUID, so the kernel merges them into one block device and
      # /models never sees the difference.
      #
      # The old idempotence check tested only "is this NQN connected at all",
      # which would have found path 1 and silently skipped path 2. Match on the
      # (traddr, host_traddr) pair instead, so each rail is tracked separately.
      path_connected() {
        target=$1
        host=$2
        for controller in /sys/class/nvme/nvme*; do
          [ -r "$controller/subsysnqn" ] || continue
          read -r controller_nqn <"$controller/subsysnqn"
          [ "$controller_nqn" = ${lib.escapeShellArg modelsStorage.modelsNqn} ] || continue
          [ -r "$controller/address" ] || continue
          read -r controller_address <"$controller/address"
          case "$controller_address" in
            *"traddr=$target"*"host_traddr=$host"*) return 0 ;;
          esac
        done
        return 1
      }

      # RDMA needs a verbs device, so a path can never silently fall back to the
      # 2.5G Realtek: if the rail's address is not on its own ConnectX port, that
      # path simply does not happen.
      connect_path() {
        interface=$1
        host=$2
        target=$3

        if path_connected "$target" "$host"; then
          echo "path $host -> $target already connected"
          return 0
        fi

        for _ in $(seq 1 100); do
          if ip -4 -o address show dev "$interface" 2>/dev/null |
            grep -Fq "inet $host/"; then
            break
          fi
          sleep 0.1
        done
        ip -4 -o address show dev "$interface" 2>/dev/null |
          grep -Fq "inet $host/" || {
            echo "fabric address $host is not on $interface;" >&2
            echo "refusing to reach the target over any other interface" >&2
            return 1
          }

        nvme connect \
          --transport=rdma \
          --traddr="$target" \
          --trsvcid=4420 \
          --nqn=${lib.escapeShellArg modelsStorage.modelsNqn} \
          --tos=${toString (config.sconfig.roceQos.dscp * 4 + 2)} \
          --host-traddr="$host"
      }

      # Path 1 is required; the rest are additive, so losing the second rail
      # costs bandwidth rather than /models itself.
      ${lib.concatStringsSep "\n      " (lib.imap1 (i: path:
        if i == 1
        then "connect_path ${path.interface} ${path.hostIp} ${path.target}"
        else "connect_path ${path.interface} ${path.hostIp} ${path.target} \\\n        || echo \"second rail unavailable; continuing degraded\" >&2"
      ) modelsPaths)}

      # Spread I/O across every live path. The default policy is "numa", which
      # on these single-socket boxes pins all traffic to one controller and
      # leaves the second card completely idle -- the whole point, undone.
      for subsystem in /sys/class/nvme-subsystem/*; do
        [ -r "$subsystem/subsysnqn" ] || continue
        read -r subsystem_nqn <"$subsystem/subsysnqn"
        [ "$subsystem_nqn" = ${lib.escapeShellArg modelsStorage.modelsNqn} ] || continue
        [ -w "$subsystem/iopolicy" ] || continue
        echo round-robin >"$subsystem/iopolicy"
      done

      # safetensors loads large checkpoints through mmap. The kernel default
      # 256 KiB read-ahead starves this NVMe/RDMA controller (127 I/O queues,
      # 128 KiB max requests): H3 transformer shards measured ~61 MiB/s and
      # ~100 s each. A 16 MiB window reduced subsequent shard loads to ~28 s.
      # blockdev takes 512-byte sectors, hence 32768 sectors = 16 MiB.
      # nvme connect returns before udev necessarily creates the stable
      # nvme-uuid symlink used by the mount. Wait briefly for that exact
      # namespace rather than silently leaving the kernel's tiny default.
      read_ahead_device=${lib.escapeShellArg modelsDevice}
      for attempt in $(seq 1 100); do
        [ -b "$read_ahead_device" ] && break
        sleep 0.1
      done

      if [ -b "$read_ahead_device" ]; then
        blockdev --setra 32768 "$read_ahead_device" \
          || echo "could not raise models read-ahead; continuing" >&2
      else
        echo "models namespace is connected but $read_ahead_device is not ready;" >&2
        echo "skipping read-ahead tuning" >&2
      fi
    '';
    preStop = ''
      nvme disconnect --nqn=${modelsStorage.modelsNqn} || true
    '';
  };

  # A successful oneshot cannot notice that the kernel later removed its
  # controller. Reconcile both the NQN and pinned block device, and replay the
  # connection plus mount transaction when either disappears.
  systemd.services.nvme-trex-models-reconcile = lib.mkIf enableCx5Fabric {
    description = "Reconcile trex models NVMe/RDMA connection";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.systemd
    ];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail

      # Count live controllers rather than answering "any?": with two rails a
      # single live path keeps /models served, so the old boolean could not tell
      # "healthy" from "degraded, running at half bandwidth".
      live_path_count() {
        count=0
        for subsystem in /sys/class/nvme-subsystem/*; do
          [ -r "$subsystem/subsysnqn" ] || continue
          read -r subsystem_nqn <"$subsystem/subsysnqn"
          [ "$subsystem_nqn" = ${lib.escapeShellArg modelsStorage.modelsNqn} ] || continue
          for controller in "$subsystem"/nvme*; do
            [ -r "$controller/state" ] || continue
            read -r controller_state <"$controller/state"
            if [ "$controller_state" = live ]; then
              count=$((count + 1))
            fi
          done
        done
        printf '%s\n' "$count"
      }

      expected_paths=${toString (builtins.length modelsPaths)}

      state=$(systemctl show --property=ActiveState --value nvme-trex-models.service)
      [ "$state" = activating ] && exit 0

      live_paths=$(live_path_count)

      if [ "$state" = active ] \
        && [ -b ${lib.escapeShellArg modelsDevice} ] \
        && [ "$live_paths" -ge 1 ]; then
        if ! systemctl is-active --quiet models.mount; then
          echo "models controller is live but models.mount is not; remounting" >&2
          systemctl restart models.mount
          exit 0
        fi
        # Degraded but serving: the data is still reachable over the surviving
        # rail, so do not touch the mount. Re-running the connector is enough --
        # it adds only the missing path and leaves the live one untouched.
        if [ "$live_paths" -lt "$expected_paths" ]; then
          echo "only $live_paths of $expected_paths NVMe paths live; restoring the missing rail" >&2
          systemctl restart nvme-trex-models.service
        fi
        exit 0
      fi

      echo "models connector, live controller, or pinned block device is absent; reconnecting" >&2
      systemctl restart nvme-trex-models.service
      systemctl restart models.mount
    '';
  };

  systemd.timers.nvme-trex-models-reconcile = lib.mkIf enableCx5Fabric {
    description = "Retry stale trex models NVMe/RDMA clients";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitInactiveSec = "1min";
      AccuracySec = "1s";
      Unit = "nvme-trex-models-reconcile.service";
    };
  };

  # disko-install seeds the persistent host keys by copying a directory onto
  # /etc/ssh. Keep that directory traversable so sshd can read per-user
  # authorized_keys after dropping privileges from root.
  systemd.tmpfiles.rules = [
    "d /etc/ssh 0755 root root -"
  ];

  # Point all HuggingFace tooling at the read-only /models snapshot and keep
  # compute nodes strictly offline w.r.t. the Hub — model acquisition belongs
  # to trex, which publishes the pinned snapshot. Setting these globally means
  # interactive ssh sessions and the hellas-ai-video runners don't need to set
  # HF_HOME.
  environment.variables = {
    HF_HOME = "/models/.cache/huggingface";
    HF_HUB_OFFLINE = "1";
    TRANSFORMERS_OFFLINE = "1";
    HF_HUB_DISABLE_TELEMETRY = "1";
    # VLLM_USE_RAY_V2_EXECUTOR_BACKEND = "0";
    # VLLM_USE_RAY_COMPILED_DAG = "1";
    # VLLM_USE_RAY_COMPILED_DAG_OVERLAP_COMM = "0";
    # RAY_EXPERIMENTAL_NOSET_HIP_VISIBLE_DEVICES = "0";
  };

  profiles.thunderbolt-bridge = {
    bridgeThunderboltNet = false;
    enableThunderboltNet = enableUsb4Tcp;
  };

  hardware."thunderbolt-ibverbs" = lib.mkMerge [
    {
      enable = lib.mkForce enableUsb4Rdma;
      blacklist.enable = lib.mkForce enableUsb4Rdma;
    }
    (lib.mkIf enableUsb4Rdma {
      loadOnBoot = true;

      config = {
        profile = "linux_perf";
        compat = "off";
        tbnet = "prefer_rdma";
        tbnet_identity = "off";
        # Use the normal LAN address for verbs GIDs and control-plane routing;
        # USB4 payload traffic still uses the native tbverbs DMA rings.
        roce_netdev = "eno1";
        lanes = "auto";
        bind_services = true;
        allocate_rings = true;
        start_rings = true;
        negotiate_native = true;
        enable_tunnels = true;
        native_data = true;
        native_fragment_striping = true;
        native_p2p_zcopy = false;
        native_p2p_host_stream = false;
        zcopy_min_bytes = 4294967295;
        native_rx_p2p_probe = false;
        native_rx_p2p_single_rx = false;
        native_rx_p2p_shared_ring_unsafe = false;
        native_rx_one_deep = false;
        native_rx_p2p_lane = 1;
        apple_data = false;
        register_verbs = true;
      };

      check = {
        enable = true;
        afterReload = true;
        requireVerbs = true;
        expectedNativeControl = "source_aware";
        # Current Strix topology exposes two ready rails per node; requiring
        # four makes otherwise successful Colmena activations fail.
        minReadyRails = 2;
        # The strix-3/4 USB4 peer currently negotiates 10 Gb/s per native rail;
        # strix-1/2 retain their 20 Gb/s expectation.
        expectedRailSpeed = if enableSharedCx5 then "10Gb/s" else "20Gb/s";
        timeoutSeconds = 75;
      };
    })
  ];

  networking = {
    inherit hostName;
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    useDHCP = lib.mkForce false;
    firewall = {
      enable = false;
    };
  };

  boot.extraModprobeConfig = lib.optionalString enableUsb4Rdma ''
    options thunderbolt xdomain=1
    options thunderbolt_net e2e=0 tx_e2e=0
  '' + ''
    options cfg80211 ieee80211_regdom=CH
    options sp5100_tco heartbeat=30 nowayout=1 action=0
  '';

  boot.kernelModules = [ "sp5100_tco" ] ++ lib.optionals enableCx5Fabric [
    "ib_umad"
    # /models arrives over NVMe-oF/RDMA from trex.
    "nvme-rdma"
  ] ++ lib.optionals enableSharedIb [ "ib_ipoib" ];

  boot.kernel.sysctl = {
    # Latency-biased network tuning for distributed inference control paths.
    # busy_{read,poll} trade CPU for lower queue wakeup latency.
    "net.core.busy_read" = 100;
    "net.core.busy_poll" = 100;
    "net.ipv4.tcp_low_latency" = 1;
    "net.ipv4.tcp_fastopen" = 3;
    # The first and second CX5 rails share the fabric L2 domain, and the LAN can
    # also see some of its broadcasts. Linux's default weak-host ARP behaviour
    # therefore made every strix-1 interface answer for 192.168.25.101: peers
    # observed the correct CX5 MAC, the second-rail CX5 MAC, and eno1's Realtek
    # MAC in response to one request. Whichever reply won poisoned the RoCE
    # neighbour and wedged RCCL init. Answer only on the interface that owns the
    # target address, and never advertise a source from another interface.
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.default.arp_ignore" = 1;
    "net.ipv4.conf.all.arp_announce" = 2;
    "net.ipv4.conf.default.arp_announce" = 2;
    # Allow intermediate nodes to forward TP control-plane packets between
    # strix machines that are not directly Thunderbolt-connected.
    "net.ipv4.ip_forward" = 1;
    # Increase socket buffers so Thunderbolt bandwidth (≥40 Gb/s) is not
    # bottlenecked by the default 4 MiB kernel cap.
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.ipv4.tcp_rmem" = "4096 87380 134217728";
    "net.ipv4.tcp_wmem" = "4096 65536 134217728";
  };

  users.users.grw.extraGroups = [ "networkmanager" ];

  # Console autologin on every getty (incl. tty0/HDMI): these are headless
  # compute nodes debugged at the bench with a screen and keyboard.
  services.getty.autologinUser = "grw";

  systemd.network =
    let
      thunderboltIp = "10.0.${toString (index + 3)}.2/24";
    in
    {
      enable = true;
      wait-online = {
        enable = true;
        anyInterface = true;
      };
      links =
        lib.optionalAttrs netboot {
          # Preserve the CX5 interface name chosen in the initrd. This MAC is
          # a separate physical port on Strix 3/4; on Strix 1/2 its firmware
          # alias and permanent Linux identity describe the one cabled rail.
          "00-netboot-lan" = {
            matchConfig.PermanentMACAddress = self.netbootLinuxMac or self.netbootMac;
            linkConfig = {
              Name = "eno1";
              # r8169 defaults the RTL8125 back to disabled unless userspace
              # requests magic-packet wake for the final Linux link
              # configuration.  This was long applied to strix-3 alone, which
              # left the other three unarmed after any clean shutdown: on
              # 2026-08-21 strix-1 missed the cluster power-on and could not be
              # woken remotely, needing a physical button press.  Verified then
              # with `ethtool eno1`: strix-3 reported "Wake-on: g", strix-2 and
              # strix-4 "Wake-on: d".  Firmware WOL must also be enabled in each
              # board's BIOS (Advanced -> Wake On LAN) for this to take effect.
              WakeOnLan = "magic";
            };
          };
        }
        // lib.optionalAttrs (enableSharedCx5 && !netbootSharesFabric) {
          "10-cx5-fabric" = {
            matchConfig.PermanentMACAddress = self.strix.cx5FabricMac;
            linkConfig.Name = vllmFabricInterface;
          };
        }
        // lib.optionalAttrs enableCx5Fabric2 {
          # Match the inventory MAC, never mlx5_N: PCI enumeration changes
          # across boots and between otherwise similar hosts.
          "11-cx5-fabric2" = {
            matchConfig.PermanentMACAddress = self.strix.cx5Fabric2Mac;
            linkConfig.Name = vllmFabric2Interface;
          };
        };
      networks = {
        "10-lan" = {
          matchConfig.Name = "eno1";
          address = [
            (network.cidrOf "lan" self.addresses.lan)
          ] ++ lib.optionals netbootSharesFabric [
            (network.cidrOf "fabric" self.addresses.fabric)
          ];
          gateway = [ network.routerIp ];
          dns = [ network.dnsIp ];
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = true;
            MulticastDNS = "yes";
          } // lib.optionalAttrs netboot {
            KeepConfiguration = "static";
          };
          linkConfig = {
            RequiredForOnline = "routable";
            # The diskless root remains live over this LAN link after stage 2.
            # Keep it at Ethernet's standard MTU: the cluster's smart-switch
            # path does not reliably pass jumbo frames, and changing eno1 to
            # 9000 here strands NFS while small ICMP packets still work.
            MTUBytes = if netboot then "1500" else "9000";
          };
        };

        # Give the inventory-selected ConnectX port its fabric (RoCE) address.
        # Its permanent MAC is renamed to cx5fabric0 by 10-cx5-fabric.link, so
        # PCI enumeration and the unused second PF cannot redirect the address.
        "15-cx5-fabric" = {
          matchConfig.Name = vllmFabricInterface;
          address = [ (network.cidrOf "fabric" self.addresses.fabric) ];
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = false;
            LinkLocalAddressing = "no";
            ConfigureWithoutCarrier = true;
            KeepConfiguration = "static";
          };
          linkConfig = {
            MTUBytes = "9000";
            RequiredForOnline = "no";
          };
        };

        # Rail 2 is a separate 192.168.26.0/24 L3 subnet over the existing
        # untagged fabric VLAN-25 L2. Its filename sorts before the broad mlx5
        # rule below, so systemd-networkd cannot leave it unaddressed.
        "15-cx5-fabric2" = lib.mkIf enableCx5Fabric2 {
          matchConfig.Name = vllmFabric2Interface;
          address = [ (network.cidrOf "fabric2" self.addresses.fabric2) ];
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

        "16-shared-cx5-unaddressed" = {
          # Driver= cannot match here: networkd resolves it with a single
          # ethtool call keyed to the ifname it holds at that instant, never
          # retried, and systemd-networkd.socket's buffered netlink replay
          # delivers each mlx5 port's pre-rename kernel name (e.g. eth1)
          # after udev has already renamed it -- that ethtool call then hits
          # ENODEV and Driver= never matches for the rest of the boot. This
          # rule exists to catch whichever mlx5 ports the more specific rules
          # above (15-cx5-fabric, 15-cx5-fabric2) did not claim by name, so it
          # cannot be pinned to one Name= or one host's PermanentMACAddress=
          # either. Match the udev ID_NET_DRIVER property instead: udev sets
          # it synchronously during the device's own add event, independent
          # of any later rename, so it is immune to the replay. No SR-IOV VFs
          # are configured on this driver anywhere in this repo, so the match
          # stays specific to physical mlx5 PFs.
          matchConfig.Property = "ID_NET_DRIVER=mlx5_core";
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

        # Direct point-to-point link to Mac. Wins over the profile's
        # 50-thunderbolt bridge match by lexical order on the iface name.
        "20-thunderbolt0" = {
          matchConfig.Name = "thunderbolt0";
          address = [ thunderboltIp ];
          networkConfig = {
            LinkLocalAddressing = "no";
            IPv6AcceptRA = false;
            ConfigureWithoutCarrier = true;
          };
          linkConfig = {
            MTUBytes = "9000";
            RequiredForOnline = "no";
          };
        };
      };
    };
}
