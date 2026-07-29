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
  # Diskless hosts boot via PXE/iPXE and run from trex's NFS store. The
  # flag lives in network.nix so the router (DHCP/TFTP) and trex
  # (exports/boot files) stay in sync with the machine config.
  netboot = self.netboot or false;
  # Per-host hardware facts (BeeGFS disk serial, CX5 port ownership, power
  # limits) live in the network.nix host record — the single inventory.
  beegfsDisk = "/dev/disk/by-id/nvme-Corsair_MP600_CORE_XT_${self.strix.beegfsDiskSerial}";
  beegfsMountPoint = "/srv/beegfs";
  enableUsb4Rdma = builtins.elem index [ 1 2 3 4 ];
  enableCx5Fabric = builtins.elem index [ 1 2 3 4 ];
  enableSharedCx5 = enableCx5Fabric;
  netbootSharesFabric = netboot && (self.netbootSharesFabric or false);

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

  vllmFabricInterface = "cx5fabric0";
  vllmHostIp =
    if enableCx5Fabric
    then network.ipOf "fabric" self.addresses.fabric
    else "10.5.0.${toString index}";
  beegfsFabricInterfaces = pkgs.writeText
    "beegfs-fabric-interfaces-${hostName}"
    "* ${vllmHostIp} 4\n";

  linuxPackagesThunderbolt =
    (pkgs.linuxPackagesFor tbvPackages.linux-thunderbolt).extend (_: super: {
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
    home-manager = {
      enable = true;
      enableDevelopment = true;
    };
    xmrig = {
      enable = false;
      package = pkgs.xmrig-zen5;
    };
  };

  system.stateVersion = "24.11";

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
  ];

  environment.etc."mft/mft.conf" = lib.mkIf enableSharedCx5 {
    source = "${pkgs.mlnx-mft}/etc/mft/mft.conf";
  };

  boot.loader.systemd-boot.configurationLimit = lib.mkForce 4;
  boot.kernelPackages = lib.mkOverride 900 linuxPackagesThunderbolt;

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
    # The PEX880xx subtree on strix-4 needs one more 1 MiB bridge window than
    # firmware allocated on the 2026-07-24 cold boot. Without reallocation the
    # NVMe link trains, but BAR 0 remains unassigned and nvme_probe returns
    # -ENODEV. Keep this scoped to the affected netboot host.
    ++ lib.optionals (netboot && index == 4) [
      "pci=realloc=on"
    ]
    # Disabled after strix-1 amdgpu failed to fetch VBIOS from ACPI VFCT while
    # booted with these experimental PCIe enumeration parameters.
    ++ lib.optionals false [
      "pci=realloc,assign-busses"
      "pcie_ports=native"
    ];

  deployment.targetHost = network.primaryIp self;
  deployment.targetUser = "grw";

  sops.secrets.mosquitto-password = mkSecret "mosquitto-password" {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  # Each Strix node contributes the large XFS partition of its dedicated
  # NVMe as one BeeGFS storage target. Restrict the daemon to the selected
  # ConnectX-5 fabric address so data connections use RoCE rather than
  # falling back to the ordinary LAN. Filtering by inventory-derived address
  # avoids coupling BeeGFS to PCI-enumeration-dependent Linux interface names.
  # services.beegfs-cluster = {
  #   meta = lib.mkIf (index == 1) {
  #     enable = true;
  #     # The metadata set is tiny for this cluster. Co-locate it on strix-1's
  #     # NVMe-backed XFS target rather than putting latency-sensitive metadata
  #     # on the BlueField's eMMC.
  #     directory = "${beegfsMountPoint}/metadata";
  #     allowFirstRunInit = false;
  #     settings = {
  #       connInterfacesFile = "${beegfsFabricInterfaces}";
  #       connRestrictOutboundInterfaces = true;
  #       storeFsUUID = self.strix.beegfsFsUUID;
  #     };
  #   };
  #   storage = {
  #     enable = true;
  #     directories = [ beegfsMountPoint ];
  #     # All four targets have been initialized and registered. Refuse to
  #     # manufacture a new target if this directory is ever unexpectedly empty.
  #     allowFirstRunInit = false;
  #     settings = {
  #       connInterfacesFile = "${beegfsFabricInterfaces}";
  #       connRestrictOutboundInterfaces = true;
  #       # Match the 4 MiB filesystem stripe chunks with 4.5 MiB of RDMA
  #       # buffers per connection.  The BeeGFS defaults total only 560 KiB
  #       # and force large transfers through repeated protocol rounds.  The
  #       # userspace storage daemon does not accept the client-only
  #       # connRDMAFragmentSize setting in BeeGFS 8.4.
  #       connRDMABufSize = 131072;
  #       connRDMABufNum = 36;
  #       storeFsUUID = self.strix.beegfsFsUUID;
  #     };
  #   };
  # };

  # sconfig.mounts.beegfs = {
  #   enable = true;
  #   clientAddresses = [ vllmHostIp ];
  # };

  # systemd.services.beegfs-root-layout = lib.mkIf (index == 1) {
  #   description = "Set the BeeGFS root stripe layout";
  #   requires = [ "mnt-beegfs.mount" ];
  #   after = [ "mnt-beegfs.mount" ];
  #   wantedBy = [ "multi-user.target" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #   };
  #   script = ''
  #     exec ${config.services.beegfs-cluster.ctlPackage}/bin/beegfs \
  #       entry set /mnt/beegfs \
  #       --pattern raid0 \
  #       --num-targets 4 \
  #       --chunk-size 4Mi \
  #       --mgmtd-addr ${config.services.beegfs-cluster.mgmtdHost}:${toString config.services.beegfs-cluster.mgmtd.grpcPort} \
  #       --tls-disable \
  #       --auth-file ${config.sops.secrets.beegfs-conn-auth.path}
  #   '';
  # };
  #
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

  # Strix 1/2 share one dual-port ConnectX-5 SharedIO adapter and Strix 3/4
  # share the other. All four physical ports connect to the CRS804 Ethernet
  # fabric; hardware.infiniband supplies the verbs/RDMA userspace.
  hardware.infiniband = {
    enable = enableCx5Fabric;
  };

  # RouterOS 7.23.2 and the HELLAS HQSFP56-200G-C1M DACs fail 100G
  # autonegotiation. Match the CRS804's forced 100G CR4 configuration after
  # every boot or PCI reset. Select the PF by inventory MAC: these SharedIO
  # adapters expose both ports to each host, but only one port is cabled.
  # A diskless host has already proved its selected CX5 rail is trained by
  # downloading iPXE, the kernel, and the initrd across it. Running mlxlink in
  # stage 2 resets the dual-port/SharedIO adapter and also drops the sibling
  # PF carrying the live NFS root. Keep forced retraining for local-disk boots,
  # but never disrupt a netboot host after the initrd handoff.
  systemd.services.cx5-fabric-link = lib.mkIf (enableCx5Fabric && !netboot) {
    description = "Force the CRS804 fabric link to 100 GbE";
    wants = lib.optionals (self.strix.bluefield or false) [ "bluefield-nic-bind.service" ];
    wantedBy = [ "network-online.target" ];
    before = [ "network-online.target" ];
    after = [ "systemd-udevd.service" ]
      ++ lib.optionals (self.strix.bluefield or false) [ "bluefield-nic-bind.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      target_mac=${lib.escapeShellArg self.strix.cx5FabricMac}
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
  # Netboot nodes mount only the BeeGFS partition. Turning netboot off makes
  # the already-provisioned root and ESP become an ordinary local NixOS boot
  # disk without repartitioning or sacrificing the storage target.
  # disko.devices.disk.beegfs = {
  #   type = "disk";
  #   device = beegfsDisk;
  #   content = {
  #     type = "gpt";
  #     partitions = {
  #       ESP = {
  #         label = "${hostName}-ESP";
  #         size = "1G";
  #         type = "EF00";
  #         content = {
  #           type = "filesystem";
  #           format = "vfat";
  #           extraArgs = [ "-F" "32" "-n" "STRIX${toString index}ESP" ];
  #           mountpoint = if netboot then null else "/boot";
  #           mountOptions = [ "umask=0077" ];
  #         };
  #       };
  #       root = {
  #         label = "${hostName}-root";
  #         size = "128G";
  #         type = "8304";
  #         content = {
  #           type = "btrfs";
  #           extraArgs = [ "-L" "${hostName}-root" ];
  #           subvolumes."@root" = {
  #             mountpoint = if netboot then null else "/";
  #           } // lib.optionalAttrs (!netboot) {
  #             mountOptions = [
  #               "compress=zstd:1"
  #               "discard=async"
  #               "noatime"
  #             ];
  #           };
  #         };
  #       };
  #       beegfs = {
  #         label = "${hostName}-beegfs";
  #         size = "100%";
  #         type = "8300";
  #         content = {
  #           type = "filesystem";
  #           format = "xfs";
  #           # XFS filesystem labels are limited to 12 characters.
  #           extraArgs = [ "-L" "STRIX${toString index}BEEGFS" ];
  #           mountpoint = beegfsMountPoint;
  #           mountOptions = [ "noatime" ];
  #         };
  #       };
  #     };
  #   };
  # };

  # Mount by GPT partition label instead of the provisioning disk's by-id path:
  # the layout must boot identically whether the drive hangs off M.2 or a USB
  # enclosure (whose enclosure-level by-id replaces the NVMe one). mkForce wins
  # over the device references disko generates from `beegfsDisk`.
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

  # fileSystems.${beegfsMountPoint} = lib.mkForce {
  #   device = "/dev/disk/by-partlabel/${hostName}-beegfs";
  #   fsType = "xfs";
  #   options = [ "noatime" "nofail" ];
  # };

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

    inputs.disko.nixosModules.disko
    inputs.nix-strix-halo.nixosModules.default
    inputs.nix-strix-halo.nixosModules.benchmark-runner
    inputs.nix-strix-halo.nixosModules.rpc-server
    inputs.nix-strix-halo.nixosModules.fastflowlm
    inputs.nix-strix-halo.nixosModules.ec-su-axb35
    inputs.nix-strix-halo.nixosModules.ryzenadj
    inputs.nix-strix-halo.nixosModules.amduprof
    inputs.nix-strix-halo.nixosModules.smu-exporter
    inputs.nix-strix-halo.nixosModules.npu-exporter

    ../../../profiles/amd-npu.nix
  ]) ++ [
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
      host = network.routerIp;
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

      # and our nfs /models
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

  # disko-install seeds the persistent host keys by copying a directory onto
  # /etc/ssh. Keep that directory traversable so sshd can read per-user
  # authorized_keys after dropping privileges from root.
  #
  # Keep model storage independent of the boot path. Netboot hosts get this
  # mount from profiles/netboot-client.nix; locally booted hosts must consume
  # the same read-only Trex export rather than silently falling back to their
  # root filesystem.
  fileSystems."/models" = lib.mkIf (!netboot) {
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

  # On every Strix host the server side owns model directory creation (chown
  # from an all_squash client fails). The local mountpoint itself is enough.
  systemd.tmpfiles.rules = [
    "d /etc/ssh 0755 root root -"
  ] ++ lib.optionals (!netboot) [
    "d /models 0755 root root -"
  ];

  # Point all HuggingFace tooling at the read-only /models snapshot and keep
  # compute nodes strictly offline w.r.t. the Hub — model acquisition belongs
  # to trex (which serves /strix-models). Setting these globally means
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

  boot.extraModprobeConfig = ''
    options thunderbolt xdomain=1
    options thunderbolt_net e2e=0 tx_e2e=0
    options cfg80211 ieee80211_regdom=CH
    options sp5100_tco heartbeat=30 nowayout=1 action=0
  '';

  boot.kernelModules = [ "sp5100_tco" ] ++ lib.optionals enableCx5Fabric [
    "ib_umad"
  ] ++ lib.optionals enableSharedIb [ "ib_ipoib" ];

  boot.kernel.sysctl = {
    # Latency-biased network tuning for distributed inference control paths.
    # busy_{read,poll} trade CPU for lower queue wakeup latency.
    "net.core.busy_read" = 100;
    "net.core.busy_poll" = 100;
    "net.ipv4.tcp_low_latency" = 1;
    "net.ipv4.tcp_fastopen" = 3;
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
            linkConfig.Name = "eno1";
          };
        }
        // lib.optionalAttrs (enableSharedCx5 && !netbootSharesFabric) {
          "10-cx5-fabric" = {
            matchConfig.PermanentMACAddress = self.strix.cx5FabricMac;
            linkConfig.Name = vllmFabricInterface;
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
          dns = [ network.routerIp ];
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
          };
          linkConfig = {
            MTUBytes = "9000";
            RequiredForOnline = "no";
          };
        };

        "16-shared-cx5-unaddressed" = {
          matchConfig.Driver = "mlx5_core";
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
