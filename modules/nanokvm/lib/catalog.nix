# Catalog of board × kernel × profile × variant combinations.
#
# One record per shipped configuration. lib/catalog.nix is the single
# source of truth for what flat `nixosConfigurations.<...>` names and
# `legacyPackages.<sys>.boards.<...>` expose; flake.nix doesn't repeat the
# matrix on the artifact side anymore.
#
# Record schema:
#   path         — list-of-string attrpath in `boards`:
#                  ["licheerv" "mainline" "live" "usb-rndis"]
#   boardName    — the module file under ./boards/ (e.g. "licheerv-nano-w")
#   kernel       — "mainline" | "vendor"
#   profile      — module name under ./profiles/ (no ".nix" suffix)
#   variant      — short variant name, used for DTB selection on the
#                  artifact side. Null when not applicable.
#   tag          — payload/runner identifier baked into filenames and
#                  the `nanokvm.kexec_target=` cmdline arg. Keep stable
#                  across refactors so on-device diagnostics don't drift.
#   mixins       — extra module file paths
#   modules      — extra inline module functions
#   artifact     — "kernel-test" | "live" | "debug" | "sd"
#                  drives which artifact-builder runs.
#   artifactArgs — key/value extras forwarded to the artifact builder
#                  (oled, rootfsBindIp, requireRootfsHostOverride,
#                  extraBootargs, includeKexec, uartConsole, usbConsole).
#   liveCfgPath  — `debug` artifacts only: the catalog path that
#                  supplies the rootfs the debug payload pivots into.
#
# Anything not listed here is intentionally absent — vendor variant
# transports, vendor.kexec runners, etc. — those don't work, so they
# don't exist.
{ lib, nanokvm }:
let
  protocol = import ./protocol.nix;

  lichee =
    kernel: pathTail: attrs:
    {
      path = [ "licheerv" kernel ] ++ pathTail;
      boardName = "licheerv-nano-w";
      inherit kernel;
    }
    // attrs;

  licheeProfile =
    kernel: pathTail: profile: artifact: tag: attrs:
    lichee kernel pathTail (
      {
        inherit profile artifact tag;
      }
      // attrs
    );

  kernelTest = kernel:
    licheeProfile
      kernel
      [ "kernel-test" ]
      "usb-kernel-test"
      "kernel-test"
      "kernel-test-${kernel}"
      { };

  debug = kernel:
    licheeProfile
      kernel
      [ "debug" ]
      "usb-debug"
      "debug"
      "debug-${kernel}"
      {
        liveCfgPath = [ "licheerv" kernel "live" "usb" ];
      };

  live =
    kernel: leaf: tag: attrs:
    licheeProfile
      kernel
      [ "live" leaf ]
      "usb-nbd-live"
      "live"
      tag
      attrs;

  usbTransport = transport: {
    modules = [ ({ ... }: { sg2002.usbGadget.network.transport = transport; }) ];
  };

  gMulti = {
    modules = [
      ({ lib, ... }: {
        boot.initrd.systemd.services.usb-gadget.enable = lib.mkForce false;
      })
    ];
    artifactArgs.extraBootargs = [
      "g_multi.use_rndis=1"
      # MACs match sg2002-usb-gadget-initrd.nix → protocol.nix.
      "g_multi.dev_addr=02:1a:11:00:01:01"
      "g_multi.host_addr=02:1a:11:00:01:02"
      "g_multi.removable=1"
      "g_multi.iManufacturer=Sipeed"
      "g_multi.iProduct=LicheeRV-Nano-NixOS"
      "g_multi.iSerialNumber=sg2002-g-multi"
    ];
  };

  oled = {
    mixins = [ (nanokvm + "/modules/oled.nix") ];
    modules = [ ({ ... }: { nanokvm.oled.enable = true; }) ];
    artifactArgs.oled = true;
  };

  wifi = {
    variant = "wifi";
    mixins = [
      (nanokvm + "/modules/sg2002-initrd-wifi.nix")
      (nanokvm + "/modules/wifi-aic8800.nix")
    ];
    modules = [
      ({ ... }: {
        # In wifi mode the rootfs NBD lives on the caller's LAN:
        # networkd brings wlan0 up via DHCP and USB-ECM stays up only
        # for the control plane. The runner must provide
        # NANOKVM_NBD_ROOTFS_HOST so this catalog remains site-neutral.
        nanokvm.nbdLive = {
          staticIface = null;
        };
      })
    ];
    artifactArgs.requireRootfsHostOverride = true;
  };

  vendorUsb = {
    # Vendor 5.10 lacks kexec-tools/nbd-client + our nbd patch — drop
    # the kexec runner from the output set. usb-boot still publishes.
    artifactArgs.includeKexec = false;
  };

  # nanokvm-pcie carrier (ethernet + WiFi + OLED footprint), mirroring
  # the `lichee` helpers above so PCIe entries stay one-liners too.
  pcie =
    kernel: pathTail: attrs:
    lib.recursiveUpdate
      {
        path = [ "pcie" kernel ] ++ pathTail;
        boardName = "nanokvm-pcie";
        inherit kernel;
        # Mainline enables the carrier's exposed UART1 as a physical rescue
        # console. Direct FIT/kexec artifacts do not inherit boot.kernelParams,
        # so carry the choice in every PCIe artifact rather than one profile.
        artifactArgs = lib.optionalAttrs (kernel == "mainline") {
          uartConsole = "ttyS1";
        };
      }
      attrs;

  pcieLive =
    kernel: tag: attrs:
    pcie kernel [ "live" "usb" ] (
      {
        profile = "usb-nbd-live";
        artifact = "live";
        inherit tag;
      }
      // attrs
    );

  pcieKernelTest = kernel:
    pcie kernel [ "kernel-test" ] {
      profile = "usb-kernel-test";
      artifact = "kernel-test";
      tag = "kernel-test-pcie-${kernel}";
    };

  # PCIe-live bring-up extras:
  #   - WiFi driver only, so wlan0 enumerates and the radio is
  #     exercisable. Association remains downstream policy.
  #   - nanokvm-server (the web UI + ATX/GPIO control), which the live
  #     profile doesn't enable on its own.
  pcieLiveExtras = {
    modules = [
      ({ ... }: {
        sg2002.wifi.enable = true;
        services.nanokvm = {
          enable = true;
          openFirewall = true;
        };
      })
    ];
  };

  # LicheeRV-Nano PicoClaw (SG2002 + expansion board, no SD slot in
  # use). USB-boot only; the live profile is NFS-rooted, not NBD.
  picoclaw =
    kernel: pathTail: attrs:
    {
      path = [ "picoclaw" kernel ] ++ pathTail;
      boardName = "licheerv-nano-picoclaw";
      inherit kernel;
    }
    // attrs;

  picoclawKernelTest = kernel:
    picoclaw kernel [ "kernel-test" ] {
      profile = "usb-kernel-test";
      artifact = "kernel-test";
      tag = "kernel-test-picoclaw-${kernel}";
      # The dwc2 gadget (net function AND ACM console) dies ~30-60 s
      # into every boot, exactly when the system goes idle after
      # bring-up. Suspect: C906 WFI cpuidle gating something the USB
      # controller needs. cpuidle.off=1 is the A/B test.
      artifactArgs.extraBootargs = [ "cpuidle.off=1" ];
    };

  picoclawLive = kernel: tag: attrs:
    picoclaw kernel [ "live" "usb" ] (
      {
        profile = "usb-nfs-live";
        artifact = "nfs-live";
        inherit tag;
        modules = [ ({ ... }: { sg2002.usbGadget.network.transport = "ncm"; }) ];
      }
      // attrs
    );
in
[
  # ===== licheerv-nano-w / mainline =====
  (kernelTest "mainline")
  # Experimental: same initrd and kernel as kernel-test, with only the
  # full-speed DT cap lifted.  Keep the stable recovery target available.
  (lichee "mainline" [ "kernel-test-hs" ] {
    profile = "usb-kernel-test";
    artifact = "kernel-test";
    tag = "kernel-test-mainline-hs";
    modules = [
      ({ pkgs, ... }: {
        sg2002.fdt = pkgs.sg2002-dtb-mainline-high-speed;
        sg2002.usbGadget.network.transport = "ncm";
      })
    ];
  })
  (debug "mainline")
  (live "mainline" "usb" "live-mainline" { })
  # The auxiliary-core variant is deliberately a separate catalog leaf: its
  # FIP starts C906L and its DT removes the matching DDR carveouts from Linux.
  # The artifact builder also selects the firmware-bearing ROM USB runner.
  (live "mainline" "usb-c906l" "live-mainline-c906l" {
    modules = [ ({ ... }: { sg2002.auxCore.enable = true; }) ];
  })
  # Explicit Timer4 lease: the evaluated auxCore configuration selects the
  # matched firmware-bearing FIP and USB runner through the artifact builder.
  (live "mainline" "usb-c906l-timer4" "live-mainline-c906l-timer4" {
    modules = [
      ({ ... }: {
        sg2002.auxCore = {
          enable = true;
          peripherals = [ "timer4" ];
        };
      })
    ];
  })
  (live "mainline" "usb-c906l-timer5" "live-mainline-c906l-timer5" {
    modules = [
      ({ ... }: {
        sg2002.auxCore = {
          enable = true;
          peripherals = [ "timer5" ];
        };
      })
    ];
  })
  (live "mainline" "usb-c906l-timer6" "live-mainline-c906l-timer6" {
    modules = [
      ({ ... }: {
        sg2002.auxCore = {
          enable = true;
          peripherals = [ "timer6" ];
        };
      })
    ];
  })
  (live "mainline" "usb-c906l-timer7" "live-mainline-c906l-timer7" {
    modules = [
      ({ ... }: {
        sg2002.auxCore = {
          enable = true;
          peripherals = [ "timer7" ];
        };
      })
    ];
  })
  # Combined timer validation image.  This remains a reversible RAM/NBD boot,
  # keeps the independent watchdog alive across switch-root, and deliberately
  # omits the NanoKVM service and benchmark-heavy live-profile packages.  No
  # peripheral test runs automatically; Linux performs only the contract-
  # gated bounded activation sequence before the operator uses the CLI.
  (live "mainline" "usb-c906l-all-timers" "live-mainline-c906l-all-timers" {
    # Keep ttyS0 for physical rescue, but do not make an unread ttyGS0 the
    # kernel console.  On this lab path there may be no host ACM reader, and
    # gadget-console backpressure is an unrelated boot-progress confound.
    artifactArgs.usbConsole = false;
    modules = [
      ({ config, lib, pkgs, ... }: {
        sg2002 = {
          auxCore = {
            enable = true;
            peripherals =
              pkgs.sg2002-c906l-profile-manifest.all-timers.peripherals;
          };
          watchdogKeeper = {
            initrd.enable = true;
            stage2.enable = true;
            healthHost = protocol.hostIp;
          };
          usbGadget.console.enable = false;
          wifi.enable = false;
        };

        services.nanokvm.enable = lib.mkForce false;
        services.openssh.enable = lib.mkForce false;
        environment.systemPackages = lib.mkForce [
          pkgs.bashInteractive
          pkgs.coreutils
          pkgs.kmod
          (pkgs.sg2002-c906l-ctl-for
            (pkgs.sg2002-c906l-contract-for config.sg2002.auxCore.peripherals))
        ];
      })
    ];
  })
  (live "mainline" "usb-rndis" "live-mainline-rndis" (usbTransport "rndis"))
  (live "mainline" "usb-ncm" "live-mainline-ncm" (usbTransport "ncm"))
  # High-speed gadget + NCM: the FS/ECM path through a usbip forwarder
  # stalls sustained NBD pulls; HS also matches U-Boot's fastboot gadget.
  (live "mainline" "usb-hs" "live-mainline-hs" {
    modules = [
      ({ pkgs, ... }: {
        sg2002.fdt = pkgs.sg2002-dtb-mainline-high-speed;
        sg2002.usbGadget.network.transport = "ncm";
      })
    ];
  })
  # Rootfs NBD over wired LAN: the initrd DHCPs eth0 and nbd-client
  # connects to the host's LAN address (NANOKVM_NBD_ROOTFS_HOST at run
  # time), leaving the USB gadget for console/control only. For boards
  # whose USB data path is compromised (e.g. usbip through a weak AP).
  (live "mainline" "eth" "live-mainline-eth" {
    modules = [
      ({ pkgs, ... }: {
        sg2002.fdt = pkgs.sg2002-dtb-mainline-eth;
        nanokvm.nbdLive.staticIface = null;

        boot.kernelModules = [ "dwmac-sophgo" ];
        sg2002.initrd.availableKernelModules = [ "dwmac-sophgo" ];
        sg2002.initrd.kernelModules = [ "dwmac-sophgo" ];

        boot.initrd.systemd.network.networks."20-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig.DHCP = "yes";
          linkConfig.RequiredForOnline = "no";
        };
        systemd.network.networks."20-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig = {
            DHCP = "yes";
            IPv6AcceptRA = true;
          };
          linkConfig.RequiredForOnline = "no";
        };
      })
    ];
  })
  (live "mainline" "usb-g-multi" "live-mainline-g-multi" gMulti)
  (live "mainline" "usb-oled" "live-mainline-oled" oled)
  # Historical kink: tag is "live-wifi-<kernel>" not "live-<kernel>-wifi".
  # Kept stable so kexec_target diagnostics don't change.
  (live "mainline" "wifi" "live-wifi-mainline" wifi)

  # ===== licheerv-nano-w / mainline / SD =====
  # Self-contained extlinux SD image for units with the RJ45 wired:
  # eth0 DHCPs in stage 2, console stays on ttyS0 (never ttyGS0 — a
  # gadget console with no host reader wedges the boot), USB gadget
  # remains for control/debug.
  (lichee "mainline" [ "sd" ] {
    profile = "sd-image-mainline";
    artifact = "sd";
    modules = [
      ({ pkgs, ... }: {
        sg2002.fdt = pkgs.sg2002-dtb-mainline-eth;
        systemd.network.networks."20-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig = {
            DHCP = "yes";
            IPv6AcceptRA = true;
          };
          linkConfig.RequiredForOnline = "no";
        };
      })
    ];
  })

  # ===== licheerv-nano-w / vendor =====
  (kernelTest "vendor")
  (debug "vendor")
  (live "vendor" "usb" "live-vendor" vendorUsb)

  # ===== nanokvm-pcie / vendor =====
  # Production SD image (vendor kernel + vendor-FIT). Network policy
  # belongs in the downstream config that imports the board module.
  (pcie "vendor" [ "sd" ] { profile = "sd-image"; artifact = "sd"; })
  # Initrd-only recovery target using the vendor SDHCI stack. Useful when
  # mainline can reach USB but cannot enumerate the card.
  (pcieKernelTest "vendor")
  # USB-NBD live for hardware bring-up: ethernet (bm-dwmac) + WiFi work
  # natively off the vendor DTS.
  (pcieLive "vendor" "live-pcie-vendor" (pcieLiveExtras // vendorUsb))

  # ===== nanokvm-pcie / mainline =====
  # Initrd-only recovery target for USB/kexec bring-up on the actual PCIe
  # carrier (same DTB as the SD image, but no stage-2 services).
  (pcieKernelTest "mainline")
  (pcie "mainline" [ "kernel-test-hs" ] {
    profile = "usb-kernel-test";
    artifact = "kernel-test";
    tag = "kernel-test-pcie-mainline-hs";
    modules = [
      ({ lib, pkgs, ... }:
        let
          autoReboot = pkgs.writeShellScript "pcie-hs-auto-reboot" ''
            ${pkgs.coreutils}/bin/sleep 300
            ${pkgs.systemd}/bin/systemctl reboot -ff
          '';
        in
        {
          sg2002.fdt = lib.mkForce pkgs.sg2002-dtb-mainline-pcie-high-speed;
          sg2002.usbGadget.network.transport = "ncm";

          # This initrd deliberately keeps the nowayout watchdog alive.  Give
          # remote tests a bounded escape if USB networking never appears.
          boot.initrd.systemd.storePaths = [ autoReboot ];
          boot.initrd.systemd.services.pcie-hs-auto-reboot = {
            description = "Return from the experimental PCIe USB test";
            wantedBy = [ "initrd.target" ];
            unitConfig.DefaultDependencies = false;
            serviceConfig = {
              Type = "oneshot";
              ExecStart = autoReboot;
            };
          };
        })
    ];
  })
  # extlinux SD image (mainline U-Boot). Ethernet via stmmac + the
  # ethernet-enabled DTB; reachable over the USB-ECM gadget too.
  (pcie "mainline" [ "sd" ] { profile = "sd-image-mainline"; artifact = "sd"; })
  # USB-NBD live exercising the full PCIe hardware — eth0 (stmmac) and
  # wlan0 (AIC8800) both come up.
  (pcieLive "mainline" "live-pcie-mainline" pcieLiveExtras)
  # Auxiliary-core product compositions are explicit catalog leaves.  They
  # retain the PCIe carrier topology while disabling SDIO WiFi, matching the
  # current C906L ownership contract and avoiding a second out-of-tree module
  # in the constrained live image.
  (pcie "mainline" [ "live" "usb-c906l" ] {
    profile = "usb-nbd-live";
    artifact = "live";
    tag = "live-pcie-mainline-c906l";
    modules = [
      ({ ... }: {
        sg2002.auxCore.enable = true;
        sg2002.wifi.enable = false;
        services.nanokvm = {
          enable = true;
          openFirewall = true;
        };
      })
    ];
  })
  (pcie "mainline" [ "live" "usb-c906l-timer4" ] {
    profile = "usb-nbd-live";
    artifact = "live";
    tag = "live-pcie-mainline-c906l-timer4";
    modules = [
      ({ ... }: {
        sg2002.auxCore = {
          enable = true;
          peripherals = [ "timer4" ];
        };
        sg2002.wifi.enable = false;
        services.nanokvm = {
          enable = true;
          openFirewall = true;
        };
      })
    ];
  })
  (pcie "mainline" [ "live" "usb-c906l-timer5" ] {
    profile = "usb-nbd-live";
    artifact = "live";
    tag = "live-pcie-mainline-c906l-timer5";
    modules = [
      ({ ... }: {
        sg2002.auxCore = {
          enable = true;
          peripherals = [ "timer5" ];
        };
        sg2002.wifi.enable = false;
        services.nanokvm = {
          enable = true;
          openFirewall = true;
        };
      })
    ];
  })
  (pcie "mainline" [ "live" "usb-c906l-timer6" ] {
    profile = "usb-nbd-live";
    artifact = "live";
    tag = "live-pcie-mainline-c906l-timer6";
    modules = [
      ({ ... }: {
        sg2002.auxCore = {
          enable = true;
          peripherals = [ "timer6" ];
        };
        sg2002.wifi.enable = false;
        services.nanokvm = {
          enable = true;
          openFirewall = true;
        };
      })
    ];
  })
  (pcie "mainline" [ "live" "usb-c906l-timer7" ] {
    profile = "usb-nbd-live";
    artifact = "live";
    tag = "live-pcie-mainline-c906l-timer7";
    modules = [
      ({ ... }: {
        sg2002.auxCore = {
          enable = true;
          peripherals = [ "timer7" ];
        };
        sg2002.wifi.enable = false;
        services.nanokvm = {
          enable = true;
          openFirewall = true;
        };
      })
    ];
  })

  # ===== licheerv-nano-w / mainline / NFS over WiFi =====
  # Same WiFi-rooted experiment as the picoclaw wifi entry, on the
  # original dev board (self-cycles its ROM loop on fuckup, so no
  # physical resets while iterating). The AIC8800 is identical.
  (lichee "mainline" [ "live" "wifi-nfs" ] {
    profile = "usb-nfs-live";
    artifact = "nfs-live";
    tag = "live-wifi-nfs-mainline";
    mixins = [
      (nanokvm + "/modules/sg2002-initrd-wifi.nix")
      (nanokvm + "/modules/wifi-aic8800.nix")
    ];
    modules = [
      ({ lib, rootWpaConf ? null, ... }: {
        sg2002.wifi.wpaConf = lib.mkDefault rootWpaConf;
        nanokvm.nfsLive.server = "192.168.23.8";
      })
    ];
  })

  # ===== licheerv-nano-w / mainline / NFS over ethernet =====
  # Same data path as the pcie NFS entry, for LicheeRV units with the
  # RJ45 wired: initrd DHCPs eth0, store mounts from the host over LAN.
  # USB carries the boot chain + console only.
  (lichee "mainline" [ "live" "eth-nfs" ] {
    profile = "usb-nfs-live";
    artifact = "nfs-live";
    tag = "live-eth-nfs-mainline";
    # No console=ttyGS0: when the USB host can't drain the ACM port (e.g.
    # the console is only reachable through a flaky forwarder), ttyGS
    # writes back up and wedge the kernel mid-boot. uartConsole stays.
    artifactArgs.usbConsole = false;
    modules = [
      ({ lib, pkgs, ... }: {
          sg2002.fdt = lib.mkForce pkgs.sg2002-dtb-mainline-eth;
          nanokvm.nfsLive.server = "192.168.23.8";
          # usb-nfs-live intentionally replaces the generic initrd module
          # list with a small, explicit set.  The current mainline config
          # builds this GMAC stack in-kernel, but keep the roots explicit so
          # the Ethernet profile remains correct if those Kconfig symbols
          # become modules in a later kernel refresh.
          boot.kernelModules = [ "dwmac-sophgo" ];
          sg2002.initrd.availableKernelModules = [
            "stmmac"
            "stmmac_platform"
            "dwmac-sophgo"
          ];
          sg2002.initrd.kernelModules = [ "dwmac-sophgo" ];
          boot.initrd.systemd.network.networks."20-eth0" = {
            matchConfig.Name = "eth0";
            networkConfig.DHCP = "yes";
            linkConfig.RequiredForOnline = "no";
          };
          systemd.network.networks."20-eth0" = {
            matchConfig.Name = "eth0";
            networkConfig = {
              DHCP = "yes";
              IPv6AcceptRA = true;
            };
            linkConfig.RequiredForOnline = "no";
          };

        })
    ];
  })

  # ===== licheerv-nano-w / mainline / NFS over USB gadget =====
  # Board on the NFS server's own USB port (trex): the store mount comes
  # from the host's gadget address directly (server == hostIp, so the
  # dwc2 usb-rx-guard is active), no LAN hairpin at all. This is also the
  # dwmac-RX-stall lifeboat: store traffic rides the USB gadget, eth0
  # stays idle for bring-up.
  (lichee "mainline" [ "live" "usb-nfs" ] {
    profile = "usb-nfs-live";
    artifact = "nfs-live";
    tag = "live-usb-nfs-mainline";
    artifactArgs.usbConsole = false;
    modules = [
      ({ ... }: {
        nanokvm.nfsLive.server = protocol.hostIp;
      })
    ];
  })

  # Reversible mainline hardware ISP lab. Boots to the ordinary control
  # shell with the independent watchdog keeper; capture starts explicitly
  # through V4L2/sg2002-h264-bridge --isp after inspecting the board.
  (live "mainline" "usb-cam-isp" "live-usb-cam-isp-mainline" {
    artifactArgs.usbConsole = false;
    artifactArgs.extraBootargs = [ "systemd.getty_auto=no" "udev.children_max=2" ];
    mixins = [ (nanokvm + "/modules/sg2002-coda.nix") (nanokvm + "/modules/sg2002-camera.nix") ];
    modules = [
      ({ pkgs, lib, ... }: {
        sg2002.fdt = pkgs.sg2002-dtb-mainline-cam;
        sg2002.watchdogKeeper.initrd.enable = true;
        sg2002.watchdogKeeper.stage2.enable = true;
        sg2002.watchdogKeeper.healthHost = protocol.hostIp;
        sg2002.wifi.enable = false;
        services.nanokvm.enable = lib.mkForce false;
        environment.systemPackages = lib.mkForce [
          pkgs.bashInteractive
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.gawk
          pkgs.findutils
          pkgs.util-linux
          pkgs.kmod
          pkgs.busybox
          pkgs.iproute2
          pkgs.systemd
          pkgs.sg2002-h264-bridge
          pkgs.procps
          (pkgs.v4l-utils.override { withGUI = false; withBPF = false; })
        ];
      })
    ];
  })

  # Same USB-gadget NFS lifeboat, plus the GC4653 camera + ethernet DTB.
  (lichee "mainline" [ "live" "usb-nfs-cam" ] {
    profile = "usb-nfs-live";
    artifact = "nfs-live";
    tag = "live-usb-nfs-cam-mainline";
    artifactArgs.usbConsole = false;
    artifactArgs.extraBootargs = [
      "systemd.getty_auto=no"
      "udev.children_max=2"
    ];
    mixins = [ (nanokvm + "/modules/sg2002-coda.nix") (nanokvm + "/modules/sg2002-camera.nix") ];
    modules = [
      ({ pkgs, ... }: {
        sg2002.fdt = pkgs.sg2002-dtb-mainline-cam;
        nanokvm.nfsLive.server = protocol.hostIp;
        nanokvm.nfsLive.prefetchStage2Systemd = true;
      })
    ];
  })

  # Same GC4653/Coda target, but keep the live NFS root on the board's RJ45.
  # USB only delivers FIP/FIT and retains the optional control gadget; camera,
  # NFS, SSH, and watchdog health use the reliable GMAC data path.
  (lichee "mainline" [ "live" "eth-nfs-cam" ] {
    profile = "usb-nfs-live";
    artifact = "nfs-live";
    tag = "live-eth-nfs-cam-mainline";
    artifactArgs.usbConsole = false;
    artifactArgs.extraBootargs = [
      "systemd.getty_auto=no"
      "udev.children_max=2"
    ];
    mixins = [ (nanokvm + "/modules/sg2002-coda.nix") (nanokvm + "/modules/sg2002-camera.nix") ];
    modules = [
      ({ pkgs, ... }: {
        sg2002.fdt = pkgs.sg2002-dtb-mainline-cam;
        nanokvm.nfsLive.server = "192.168.23.8";
        nanokvm.nfsLive.prefetchStage2Systemd = true;
        sg2002.watchdogKeeper.healthHost = "192.168.23.8";

        boot.initrd.systemd.network.networks."20-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig = {
            DHCP = "yes";
            KeepConfiguration = "dynamic";
          };
          linkConfig.RequiredForOnline = "no";
        };
        systemd.network.networks."20-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig = {
            DHCP = "yes";
            KeepConfiguration = "dynamic";
          };
          linkConfig.RequiredForOnline = "no";
        };
      })
    ];
  })

  # Explicitly separate audio laboratory image.  It selects the shared,
  # opt-in onboard ALSA kernel but neither installs a service nor publishes
  # RTSP: an operator must manually select a private lab URL and run the
  # PCMA bridge.  Production camera artifacts remain video-only.
  (lichee "mainline" [ "live" "eth-nfs-cam-pcma-test" ] {
    profile = "usb-nfs-live";
    artifact = "nfs-live";
    tag = "live-eth-nfs-cam-pcma-test-mainline";
    artifactArgs.usbConsole = false;
    artifactArgs.extraBootargs = [
      "systemd.getty_auto=no"
      "udev.children_max=2"
    ];
    mixins = [ (nanokvm + "/modules/sg2002-coda.nix") (nanokvm + "/modules/sg2002-camera.nix") ];
    modules = [
      ({ pkgs, ... }: {
        sg2002 = {
          fdt = pkgs.sg2002-dtb-mainline-cam;
          audio.enable = true;
          watchdogKeeper.healthHost = "192.168.23.8";
        };
        nanokvm.nfsLive = {
          server = "192.168.23.8";
          prefetchStage2Systemd = true;
        };
        environment.systemPackages = [
          pkgs.sg2002-h264-bridge-pcma
          pkgs.sg2002-alsa-kernel-test
        ];

        boot.initrd.systemd.network.networks."20-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig = {
            DHCP = "yes";
            KeepConfiguration = "dynamic";
          };
          # Stage 2 must renew the same lease that initrd obtained.  Without
          # an explicit MAC client ID the two networkd instances used distinct
          # identifiers and the DHCP server assigned two eth0 addresses.
          dhcpV4Config.ClientIdentifier = "mac";
          linkConfig.RequiredForOnline = "no";
        };
        systemd.network.networks."20-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig = {
            DHCP = "yes";
            KeepConfiguration = "dynamic";
          };
          dhcpV4Config.ClientIdentifier = "mac";
          linkConfig.RequiredForOnline = "no";
        };
      })
    ];
  })

  # ===== nanokvm-pcie / mainline / NFS over ethernet =====
  # The cleanest data path of all: the PCIe carrier's RJ45. eth0 does
  # DHCP in the initrd (dwmac-sophgo), the root-nfs service mounts
  # trex over the LAN — no dwc2 data, no WiFi. Runs on the router's
  # self-cycling board, so iteration needs no physical resets.
  (pcie "mainline" [ "live" "nfs" ] {
    profile = "usb-nfs-live";
    artifact = "nfs-live";
    tag = "live-pcie-nfs-mainline";
    # Direct USB runners do not inherit boot.kernelParams. Carry the two
    # low-memory stage-2 limits explicitly.
    artifactArgs.extraBootargs = [
      "systemd.getty_auto=no"
      "udev.children_max=2"
      # The PCIe carrier's 128x64 SSD1306 is usable with the default font,
      # but only as a cramped 16x4 display. Do not rotate this panel.
      "fbcon=font:MINI4x6"
    ];
    mixins = [ (nanokvm + "/modules/ethernet.nix") ];
    modules = [
      ({ lib, pkgs, ... }: {
        nanokvm.nfsLive.server = "192.168.23.8";
        # Ethernet is the root transport for this capture image. Avoid the
        # absent AIC8800 SDIO probe and its repeated mmc1 command timeouts.
        sg2002.fdt = lib.mkForce pkgs.sg2002-dtb-mainline-pcie-nowifi;
        sg2002.wifi.enable = lib.mkForce false;
        # A/B the stage-2 PID1 handoff: warm only systemd's direct ELF
        # dependencies from the mounted NFS store before switch-root.
        nanokvm.nfsLive.prefetchStage2Systemd = true;
        # This Ethernet-rooted image is the capture bring-up environment.
        # Avoid a permanent `top` process and bound volatile logging so CMA
        # migration does not force the tiny system into boot-time OOM.
        nanokvm.oled.enable = lib.mkForce false;
        services.journald.extraConfig = ''
          Storage=volatile
          RuntimeMaxUse=4M
        '';
        systemd.services.sshd.serviceConfig.ExecStartPre = [
          "${pkgs.coreutils}/bin/install -d -m 0555 -o root -g root /var/empty"
        ];
        security.wrappers = {
          mount.enable = lib.mkForce false;
          newgidmap.enable = lib.mkForce false;
          newgrp.enable = lib.mkForce false;
          newuidmap.enable = lib.mkForce false;
          sg.enable = lib.mkForce false;
          sudo.enable = lib.mkForce false;
          sudoedit.enable = lib.mkForce false;
          umount.enable = lib.mkForce false;
        };
        systemd.services.lastlog2-import.enable = lib.mkForce false;
        systemd.suppressedSystemUnits = [
          "systemd-journal-catalog-update.service"
          "systemd-update-done.service"
        ];
        boot.initrd.systemd.services.usb-debug-acm-status.enable =
          lib.mkForce false;
        sg2002.initrd.availableKernelModules = [
          "stmmac"
          "stmmac_platform"
          "dwmac-sophgo"
        ];
        sg2002.initrd.kernelModules = [ "dwmac-sophgo" ];
        # The store is already mounted over this DHCP lease when initrd
        # networkd hands the interface to stage 2. Preserve it until the new
        # manager has renewed the lease; dropping it deadlocks every uncached
        # executable on the NFS store. Pin the carrier's fleet MAC before the
        # first DHCP request as well, so router assigns its reserved .17.
        boot.initrd.systemd.network.networks."20-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig = {
            DHCP = "yes";
            KeepConfiguration = "dynamic";
          };
          linkConfig = {
            MACAddress = "02:4b:56:4d:00:17";
            RequiredForOnline = "no";
          };
        };
        systemd.network.networks."20-eth0" = {
          networkConfig.KeepConfiguration = "dynamic";
          linkConfig.MACAddress = "02:4b:56:4d:00:17";
        };
      })
    ];
  })

  # ===== licheerv-nano-picoclaw / mainline =====
  # Initrd-only recovery target — the first thing to run on new silicon.
  (picoclawKernelTest "mainline")
  (picoclaw "mainline" [ "kernel-test-hs" ] {
    profile = "usb-kernel-test";
    artifact = "kernel-test";
    tag = "kernel-test-picoclaw-mainline-hs";
    artifactArgs.extraBootargs = [ "cpuidle.off=1" ];
    modules = [
      ({ pkgs, ... }: {
        sg2002.fdt = pkgs.sg2002-dtb-mainline-nowifi-high-speed;
        sg2002.usbGadget.network.transport = "ncm";
      })
    ];
  })
  # USB-booted, NFS-rooted live system (replaces the NBD transport).
  #
  # Bring-up note 2026-07-27: with the WiFi DTB (sdhci1 enabled), the
  # fragile AIC8800 init sequence spins on sdhci1 timeouts and — per
  # the nowifi dtsi's own comment — the SDIO probing contends with the
  # USB gadget for the SoC bus, killing usb0's data path mid-boot.
  # Booting the nowifi DTB avoids that entirely. The wifi-aic8800
  # mixin returns in a follow-up entry once the base boot is solid.
  (picoclawLive "mainline" "live-picoclaw-mainline" {
    # Direct USB runners construct the command line themselves rather than
    # using boot.loader, so carry the getty-generator override explicitly.
    artifactArgs.extraBootargs = [
      "systemd.getty_auto=no"
      "udev.children_max=2"
    ];
    modules = [
      ({ pkgs, ... }: {
        sg2002.fdt = pkgs.sg2002-dtb-mainline-nowifi;
        sg2002.usbGadget.network.transport = "ncm";
      })
    ];
  })

  # Board-exclusive C906L display lab.  The generic C906L fastboot FIP has no
  # pre-Linux splash, so every visible pixel is attributable to the activated
  # Rust service.  Keep this RAM/NBD recovery image deliberately small and
  # watchdog-backed; Linux owns neither SPI1 nor any GPIOA line in its DT.
  (picoclaw "mainline" [ "live" "usb-c906l-lcd" ] {
    profile = "usb-nbd-live";
    artifact = "live";
    tag = "live-picoclaw-c906l-lcd";
    mixins = [ (nanokvm + "/modules/picoclaw-c906l-lcd.nix") ];
    artifactArgs = {
      usbConsole = false;
      # Direct USB runners construct the command line independently of
      # boot.kernelParams, so repeat the low-memory stage-2 limits here.
      extraBootargs = [
        "systemd.getty_auto=no"
        "udev.children_max=2"
      ];
    };
    modules = [
      ({ config, lib, pkgs, ... }: {
        sg2002 = {
          watchdogKeeper = {
            initrd.enable = true;
            stage2.enable = true;
            healthHost = protocol.hostIp;
          };
        };

        services.openssh.enable = lib.mkForce false;
        services.userborn.static = true;
        zramSwap.enable = lib.mkForce false;
        nanokvm.usbControl.kexec.enable = lib.mkForce false;
        systemd.oomd.enable = false;
        systemd.network.wait-online.enable = false;
        boot.kernelParams = [
          "systemd.getty_auto=no"
          "udev.children_max=2"
        ];
        environment.systemPackages = lib.mkForce [
          pkgs.bashInteractive
          pkgs.coreutils
          pkgs.kmod
          pkgs.sg2002-c906l-drm-test
          (pkgs.sg2002-c906l-ctl-for
            (pkgs.sg2002-c906l-contract-for
              config.sg2002.auxCore.peripherals))
        ];
      })
    ];
  })

  # Persistent counterpart to the RAM/NBD C906L LCD test.  It uses the same
  # contract/FIP/DT and DRM driver, but its root lives on an SD card.  The
  # profile requires an explicit SSH public key.  Wi-Fi power is mediated by
  # the C906L because GPIOA26 is part of its exclusive GPIOA lease.
  (picoclaw "mainline" [ "sd" "c906l-lcd" ] {
    profile = "sd-image-picoclaw-c906l";
    artifact = "sd";
  })

  # Dedicated onboard-LCD sibling of the proven headless USB/NFS boot.
  # It preserves the no-WiFi base and low-memory limits, but swaps in the
  # PicoClaw SPI1/GPIO DTB and runs a persistent ST7789 visible self-test.
  (picoclaw "mainline" [ "live" "usb-lcd" ] {
    profile = "usb-nfs-live";
    artifact = "nfs-live";
    tag = "live-picoclaw-lcd-mainline";
    artifactArgs.extraBootargs = [
      "systemd.getty_auto=no"
      "udev.children_max=2"
    ];
    mixins = [ (nanokvm + "/modules/picoclaw-lcd.nix") ];
    modules = [
      ({ pkgs, ... }: {
        nanokvm.picoclawLcd.enable = true;
        sg2002.fdt = pkgs.sg2002-dtb-mainline-picoclaw-lcd;
        sg2002.usbGadget.network.transport = "ncm";
      })
    ];
  })

  # Full-speed ECM sibling for hosts where NCM aggregation wedges the host TX
  # queue before the NFS root can reach stage 2. Keep the proven PicoClaw LCD
  # DTB, clocks, FIFO sizing and bootargs unchanged so this isolates only the
  # USB network framing (cdc_ether instead of cdc_ncm).
  (picoclaw "mainline" [ "live" "usb-lcd-ecm" ] {
    profile = "usb-nfs-live";
    artifact = "nfs-live";
    tag = "live-picoclaw-lcd-mainline-ecm";
    artifactArgs.extraBootargs = [
      "systemd.getty_auto=no"
      "udev.children_max=2"
    ];
    mixins = [ (nanokvm + "/modules/picoclaw-lcd.nix") ];
    modules = [
      ({ pkgs, ... }: {
        nanokvm.picoclawLcd.enable = true;
        sg2002.fdt = pkgs.sg2002-dtb-mainline-picoclaw-lcd;
        sg2002.usbGadget.network.transport = "ecm";
      })
    ];
  })

  # Same full-speed isolation test using the f_rndis/rndis_host data path.
  # Keep this separate from the ECM and NCM entries: SG2002 USB transport
  # reliability is empirical, and the three function drivers frame bulk OUT
  # traffic differently.
  (picoclaw "mainline" [ "live" "usb-lcd-rndis" ] {
    profile = "usb-nfs-live";
    artifact = "nfs-live";
    tag = "live-picoclaw-lcd-mainline-rndis";
    artifactArgs.extraBootargs = [
      "systemd.getty_auto=no"
      "udev.children_max=2"
    ];
    mixins = [ (nanokvm + "/modules/picoclaw-lcd.nix") ];
    modules = [
      ({ pkgs, ... }: {
        nanokvm.picoclawLcd.enable = true;
        sg2002.fdt = pkgs.sg2002-dtb-mainline-picoclaw-lcd;
        sg2002.usbGadget.network.transport = "rndis";
      })
    ];
  })

  # High-speed sibling of the LCD/NFS system.  This intentionally keeps the
  # production usb-lcd artifact on its proven full-speed DTB until sustained
  # NFS workloads are verified on the other SG2002 boards too.
  (picoclaw "mainline" [ "live" "usb-lcd-hs" ] {
    profile = "usb-nfs-live";
    artifact = "nfs-live";
    tag = "live-picoclaw-lcd-mainline-hs";
    artifactArgs.extraBootargs = [
      "systemd.getty_auto=no"
      "udev.children_max=2"
    ];
    artifactArgs.usbConsole = false;
    mixins = [ (nanokvm + "/modules/picoclaw-lcd.nix") ];
    modules = [
      ({ pkgs, ... }: {
        nanokvm.picoclawLcd.enable = true;
        sg2002.fdt = pkgs.sg2002-dtb-mainline-picoclaw-lcd-high-speed;
        sg2002.usbGadget.network.transport = "ncm";
      })
    ];
  })

  # WiFi-booted variant: the dwc2 gadget net function wedges on this
  # unit (see usb-nfs-live.nix and the bring-up note above), so the
  # store mount rides the AIC8800 over the LAN instead. USB stays on
  # for console + debug shell + kexec control. The NFS export is
  # trex's /export/nix-store, already served to 192.168.23.0/24.
  (picoclaw "mainline" [ "live" "wifi" ] {
    profile = "usb-nfs-live";
    artifact = "nfs-live";
    tag = "live-wifi-picoclaw-mainline";
    mixins = [
      (nanokvm + "/modules/sg2002-initrd-wifi.nix")
      (nanokvm + "/modules/wifi-aic8800.nix")
    ];
    modules = [
      ({ lib, rootWpaConf ? null, ... }: {
        sg2002.wifi.wpaConf = lib.mkDefault rootWpaConf;
        # NFS root over the LAN, served by trex. Runtime override:
        # NANOKVM_NFS_SERVER env → nanokvm.nfs_server= cmdline arg.
        nanokvm.nfsLive.server = "192.168.23.8";
        sg2002.watchdogKeeper.healthHost = "192.168.23.8";
      })
    ];
  })

  # Bluetooth is an explicit PicoClaw experiment, never an implicit change
  # to the WiFi-root artifact.  It uses the AIC8800's shared SDIO mailbox;
  # keep USB debug and the known-good WiFi/NFS transport unchanged.
  (picoclaw "mainline" [ "live" "wifi-bluetooth" ] {
    profile = "usb-nfs-live";
    artifact = "nfs-live";
    tag = "live-wifi-bluetooth-picoclaw-mainline";
    mixins = [
      (nanokvm + "/modules/sg2002-initrd-wifi.nix")
      (nanokvm + "/modules/wifi-aic8800.nix")
    ];
    modules = [
      ({ lib, rootWpaConf ? null, ... }: {
        sg2002.bluetooth.enable = true;
        sg2002.wifi.wpaConf = lib.mkDefault rootWpaConf;
        nanokvm.nfsLive.server = "192.168.23.8";
        sg2002.watchdogKeeper.healthHost = "192.168.23.8";
      })
    ];
  })

  # PicoClaw LCD sibling of the WiFi-root fallback. USB still performs the
  # stateless ROM/FIP/FIT handoff and exposes its control gadget, but the
  # AIC8800 carries NFS and SSH so a wedged dwc2 bulk-OUT path cannot take
  # the live root down with it.
  (picoclaw "mainline" [ "live" "usb-lcd-wifi" ] {
    profile = "usb-nfs-live";
    artifact = "nfs-live";
    tag = "live-wifi-picoclaw-lcd-mainline";
    artifactArgs = {
      usbConsole = false;
      extraBootargs = [
        "systemd.getty_auto=no"
        "udev.children_max=2"
      ];
    };
    mixins = [
      (nanokvm + "/modules/picoclaw-lcd.nix")
      (nanokvm + "/modules/sg2002-initrd-wifi.nix")
      (nanokvm + "/modules/wifi-aic8800.nix")
    ];
    modules = [
      ({ lib, pkgs, rootWpaConf ? null, ... }: {
        nanokvm.picoclawLcd.enable = true;
        sg2002.fdt = pkgs.sg2002-dtb-mainline-picoclaw-lcd-wifi;
        sg2002.wifi.wpaConf = lib.mkDefault rootWpaConf;
        nanokvm.nfsLive.server = "192.168.23.8";
        sg2002.watchdogKeeper.healthHost = "192.168.23.8";
      })
    ];
  })
]
