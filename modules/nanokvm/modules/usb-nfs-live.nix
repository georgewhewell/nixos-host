# NFS-backed live root for SG2002 boards (PicoClaw bring-up). The Nix
# store is a read-only NFSv4 export from the dev host's kernel nfsd
# (trex exports /export/nix-store — a bind of /nix/store — to the LAN
# and to the USB-link CIDR; see the netboot-server profile in
# ../nixos-config). The export is mounted directly and read-only at
# /nix/store. It is completely stateless: / is tmpfs, nothing writable
# is exported, and every boot starts from the same pristine image
# (fresh ssh host keys included —
# use StrictHostKeyChecking=accept-new).
#
# The mount is performed by an initrd service, not fstab, because the
# client address is not always knowable at build time: on USB-boots it
# is the static usb0 address, on WiFi boots it is whatever DHCP hands
# wlan0. The service waits for a route to the server, derives
# clientaddr from it, and mounts the read-only store directly.
#
# Pairs with ./usb-control.nix (kexec control socket, debug shell,
# networkd config) exactly like the NBD live module does.
{ config
, lib
, pkgs
, ...
}:
let
  protocol = import ../lib/protocol.nix;
  mkUsbRxGuard = import ../lib/sg2002-usb-rx-guard.nix { inherit lib; };
  cfg = config.nanokvm.nfsLive;
  usbRoot = cfg.server == protocol.hostIp;

  # The initrd normally executes its own systemd from the cpio image, then
  # switch-root execs the stage-2 copy from the NFS-mounted store. On the
  # C906, faulting in that new PID 1 and its five direct ELF dependencies can
  # make an otherwise-complete handoff look like a 20-second hang. Keep this
  # A/B deliberately narrow: warm only the files ldd reports for systemd
  # itself, never the complete systemd/unit closure.
  # Use the configured systemd package for every initrd helper as well as
  # stage 2. Platform overlays (for example the SG2002 old-root cleanup)
  # replace config.systemd.package; referring to pkgs.systemd here can leave
  # an unpatched, absent store path in initrd-cleanup.service.
  stage2SystemdPackage = config.systemd.package;
  stage2SystemdMajor = lib.versions.major stage2SystemdPackage.version;
  stage2SystemdPrefetch = pkgs.writeShellScript "nanokvm-prefetch-stage2-systemd" ''
    set -u
    bb=${pkgs.busybox}/bin/busybox
    started="$($bb date +%s 2>/dev/null || echo 0)"
    total=0
    failed=0

    read_one() {
      file="$1"
      if [ ! -f "$file" ]; then
        echo "nfs-live-prefetch: missing $file" > /dev/kmsg
        failed=$((failed + 1))
        return 0
      fi
      bytes="$($bb stat -c %s "$file" 2>/dev/null || echo 0)"
      if $bb dd if="$file" of=/dev/null bs=1048576 2>/dev/null; then
        total=$((total + bytes))
      else
        echo "nfs-live-prefetch: read failed $file" > /dev/kmsg
        failed=$((failed + 1))
      fi
    }

    read_one ${lib.escapeShellArg "${stage2SystemdPackage}/lib/systemd/systemd"}
    read_one ${lib.escapeShellArg "${stage2SystemdPackage}/lib/systemd/libsystemd-core-${stage2SystemdMajor}.so"}
    read_one ${lib.escapeShellArg "${stage2SystemdPackage}/lib/systemd/libsystemd-shared-${stage2SystemdMajor}.so"}
    read_one ${lib.escapeShellArg "${pkgs.glibc}/lib/libc.so.6"}
    read_one ${lib.escapeShellArg "${pkgs.glibc}/lib/libm.so.6"}
    read_one ${lib.escapeShellArg "${pkgs.glibc}/lib/ld-linux-riscv64-lp64d.so.1"}

    finished="$($bb date +%s 2>/dev/null || echo "$started")"
    duration=$((finished - started))
    echo "nfs-live-prefetch: stage2 systemd direct ELF files ''${total} bytes in ''${duration}s (failed=''${failed})" > /dev/kmsg
    exit 0
  '';

  runRootNfs = pkgs.writeShellScript "nanokvm-run-root-nfs" ''
    set -u
    # busybox mount handles -t nfs4/-o fine (kernel-direct mount, no
    # helper needed). util-linux was pulled into the initrd for this
    # earlier; it costs ~5 MB of initrd, which matters on a 190 MB
    # board where the whole cpio unpacks into page cache at boot.
    export PATH=${lib.makeBinPath [ pkgs.busybox ]}

    server=${lib.escapeShellArg cfg.server}
    export_path=${lib.escapeShellArg cfg.storeExport}

    # Site overrides travel on the kernel cmdline (runner-appended):
    #   nanokvm.nfs_server=<ip>  nanokvm.nfs_export=<pseudo-path>
    for o in $(cat /proc/cmdline); do
      case "$o" in
        nanokvm.nfs_server=*) server="''${o#nanokvm.nfs_server=}" ;;
        nanokvm.nfs_export=*) export_path="''${o#nanokvm.nfs_export=}" ;;
      esac
    done

    echo "root-nfs: waiting for a route to $server" > /dev/kmsg
    myip=""
    for _ in $(seq 1 240); do
      out="$(ip -4 route get "$server" 2>/dev/null || true)"
      case "$out" in
        *" src "*)
          myip="$(echo "$out" | sed -n 's/.*src \([0-9.]*\).*/\1/p')"
          [ -n "$myip" ] && break
          ;;
      esac
      sleep 0.5
    done
    if [ -z "$myip" ]; then
      echo "root-nfs: no route to $server after 120s" > /dev/kmsg
      exit 1
    fi

    echo "root-nfs: mounting $server:$export_path (clientaddr $myip)" > /dev/kmsg
    mkdir -p /sysroot/nix/store
    opts="vers=4.2,addr=$server,clientaddr=$myip,hard,ro,nocto,actimeo=600"
    n=0
    until mount -t nfs4 -o "$opts" "$server:$export_path" /sysroot/nix/store; do
      n=$((n + 1))
      if [ "$n" -ge 90 ]; then
        echo "root-nfs: mount of $server:$export_path failed after 90 tries" > /dev/kmsg
        exit 1
      fi
      sleep 1
    done

    echo "root-nfs: /nix/store mounted read-only from NFS" > /dev/kmsg
  '';

  # See services.usb-rx-guard below. An active host probe failing while RX
  # is stuck for two short windows triggers a full dwc2 re-probe. Keep
  # both the script and its only executable in /run: the guard must still
  # be able to recover the link when the NFS-backed store is unreachable.
  rxGuardRuntime = "/run/nanokvm-usb-rx-guard";
  rxGuardBusybox = "/run/nanokvm-usb-rx-guard-busybox";
  rxGuardStaticBusybox = pkgs.pkgsStatic.busybox;
  rxGuardSource = pkgs.writeText "nanokvm-usb-rx-guard" (mkUsbRxGuard {
    busybox = rxGuardBusybox;
    hostIp = protocol.hostIp;
  });

  rxGuardInstall = pkgs.writeShellScript "nanokvm-install-usb-rx-guard" ''
    set -eu
    ${pkgs.busybox}/bin/busybox cp -fL ${rxGuardStaticBusybox}/bin/busybox ${rxGuardBusybox}
    ${pkgs.busybox}/bin/busybox cp -f ${rxGuardSource} ${rxGuardRuntime}
    ${pkgs.busybox}/bin/busybox chmod 0755 ${rxGuardBusybox} ${rxGuardRuntime}
  '';
in
{
  imports = [
    ./usb-control.nix
  ];

  options.nanokvm.nfsLive = with lib; {
    server = mkOption {
      type = types.str;
      default = protocol.hostIp;
      description = ''
        IP the target mounts its NFS export from. Defaults to the
        USB-ECM host address; point it at the host's LAN address for
        WiFi-booted variants. Overridable at runtime with the
        nanokvm.nfs_server= kernel cmdline arg.
      '';
    };
    storeExport = mkOption {
      type = types.str;
      default = "/nix-store";
      description = "NFSv4 pseudo-path of the read-only store export.";
    };
    prefetchStage2Systemd = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Before switch-root, pre-read only stage-2 systemd and its direct
        glibc/libsystemd ELF dependencies from the mounted NFS store. This
        is an isolated boot-latency A/B for slow C906 NFS page faults; read
        failures are non-fatal and reported to the kernel log.
      '';
    };
  };

  config = {
    nanokvm.usbControl = {
      initrd.enable = true;
      stage2.enable = true;
    };

    # / and /tmp only. The store mounts (NFS ro + tmpfs upper +
    # overlay) are done by nanokvm-root-nfs.service in the initrd —
    # clientaddr is runtime-derived there (static usb0 vs DHCP wlan0).
    fileSystems = lib.mkForce {
      "/" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=0755" ];
      };
      "/tmp" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=1777" ];
      };
    };

    # NFS is built into this kernel, and runRootNfs intentionally invokes
    # BusyBox mount. Advertising NFS through the generic NixOS helper
    # lists pulls target nfs-utils (and BIND/Kerberos/SASL) into this tiny live
    # closure without participating in the mount at all.
    boot.supportedFilesystems = lib.mkForce [ ];
    boot.initrd.supportedFilesystems = lib.mkForce [ ];

    # No NFS modules are required — but erofs/loop stay for the kexec payload
    # transport.
    sg2002.initrd.pruneKernelModules = true;
    sg2002.initrd.availableKernelModules = [
      "af_packet"
      "erofs"
      "loop"
    ];

    boot.initrd.network.flushBeforeStage2 = lib.mkForce false;

    boot.initrd.systemd = {
      # The store mount itself. Runs before initrd-root-fs.target so
      # the find-nixos-closure logic sees /sysroot/nix/store; retries
      # inside the script cover slow network bring-up (DHCP on wlan0).
      services.nanokvm-root-nfs = {
        description = "Mount the NFS live root store";
        wantedBy = [ "initrd-root-fs.target" ];
        before = [ "initrd-root-fs.target" "initrd-find-etc.service" ];
        after = [
          "systemd-networkd.service"
          "usb-gadget.service"
        ];
        wants = [ "systemd-networkd.service" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = runRootNfs;
          TimeoutStartSec = "300s";
        };
      };

      # initrd-find-etc (the nixos-init /etc-overlay machinery) needs
      # the store already mounted — it resolves $toplevel/init under
      # /sysroot. It raced us once and failed the whole switch-root.
      services.initrd-find-etc = {
        after = [ "nanokvm-root-nfs.service" ];
        wants = [ "nanokvm-root-nfs.service" ];
      };

      # This is intentionally ordered on the switch-root target rather than
      # initrd.target: the NFS mount must exist, and the read should be the
      # last useful work before the new PID 1 is exec'd.
      services.nanokvm-prefetch-stage2-systemd = lib.mkIf cfg.prefetchStage2Systemd {
        description = "Warm stage-2 systemd ELF files from the NFS store";
        wantedBy = [ "initrd-switch-root.target" ];
        before = [ "initrd-switch-root.target" ];
        after = [ "nanokvm-root-nfs.service" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = stage2SystemdPrefetch;
          TimeoutStartSec = "30s";
        };
      };

      # Keep the USB debug network alive when the initrd drops to
      # emergency mode (e.g. the store mount fails). The default
      # emergency.target isolate tears the gadget down and leaves the
      # board unreachable; with these, the debug shell on 2323 stays up
      # for post-mortem debugging.
      targets.emergency.wants = [
        "usb-gadget.service"
        "usb-debug-network.service"
        "usb-debug-shell.service"
        "usb-debug-acm-status.service"
      ];
      services = {
        # `isolate initrd-switch-root.target` stops networkd and the RX
        # guard before stage 2 can adopt them. A plain start is the proven
        # network-root handoff used by usb-nbd-live: PID 1 switches root
        # without creating a blind window on the transport carrying the
        # store. It also avoids spuriously starting the completed NFS mount
        # service a second time during the isolate transaction.
        initrd-cleanup = {
          overrideStrategy = "asDropinIfExists";
          serviceConfig.ExecStart = lib.mkForce [
            ""
            "${stage2SystemdPackage}/bin/systemctl --no-block start initrd-switch-root.target"
          ];
        };

        # The NFS store rides over usb0, so tearing the gadget down during
        # initrd cleanup removes stage 2's executable files halfway through
        # switch-root. Leave the configfs gadget and network device in the
        # kernel; the stage-2 usb-gadget unit below adopts them without
        # re-enumerating.
        usb-gadget = {
          unitConfig = {
            IgnoreOnIsolate = true;
            SurviveFinalKillSignal = true;
          };
          serviceConfig = {
            ExecStop = lib.mkForce [ "" ];
            KillMode = "none";
            SendSIGKILL = false;
          };
        };
        usb-debug-network.unitConfig.IgnoreOnIsolate = true;
        usb-debug-shell.unitConfig.IgnoreOnIsolate = true;
        usb-debug-acm-status.unitConfig.IgnoreOnIsolate = true;


        # dwc2 RX-stall guard for the USB-root profile. On this unit the gadget's OUT path
        # (device RX) wedges 30-90 s into boot while the IN path
        # (console, target TX) keeps working — host sees
        # `cdc_* transmit queue 0 timed out`, target usb0 RX counter
        # freezes. Only a full dwc2 platform-driver re-probe clears it;
        # a configfs UDC detach/rebind does not. Signature we recover on:
        # The target's asynchronous host probe produced no RX for two windows
        # in a row. The probe is deliberately not awaited: the full NCM wedge
        # can block its syscall even though the separate ACM IN path lives.
        usb-rx-guard = lib.mkIf usbRoot {
          description = "Rebind the USB gadget when its RX path stalls";
          wantedBy = [ "initrd.target" ];
          after = [ "usb-gadget.service" "usb-debug-network.service" ];
          wants = [ "usb-gadget.service" "usb-debug-network.service" ];
          unitConfig = {
            DefaultDependencies = false;
            IgnoreOnIsolate = true;
            RefuseManualStop = true;
            SurviveFinalKillSignal = true;
          };
          serviceConfig = {
            ExecStartPre = rxGuardInstall;
            ExecStart = "${rxGuardBusybox} sh ${rxGuardRuntime}";
            Restart = "always";
            RestartSec = "1s";
          };
        };
      };
      storePaths = [ runRootNfs ]
        ++ lib.optional cfg.prefetchStage2Systemd stage2SystemdPrefetch
        ++ lib.optionals usbRoot [
          rxGuardInstall
          rxGuardSource
          rxGuardStaticBusybox
        ];
    };

    # The initrd instance created the configfs gadget that carries the live
    # NFS mount. Mark the corresponding stage-2 unit active without running
    # the generic setup script: that script intentionally unbinds the UDC and
    # re-probes dwc2, which would sever the store during switch-root.
    systemd.services.usb-gadget = {
      description = "Preserve the initrd USB gadget across switch-root";
      unitConfig = {
        DefaultDependencies = false;
        IgnoreOnIsolate = true;
        RefuseManualStop = true;
        SurviveFinalKillSignal = true;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
        ExecStop = lib.mkForce [ "" ];
        KillMode = "none";
        SendSIGKILL = false;
      };
    };

    # The initrd guard survives switch-root. If PID 1 ever has to restart it
    # in stage 2, its /run copy remains available without an NFS store read.
    systemd.services.usb-rx-guard = lib.mkIf usbRoot {
      description = "Rebind the USB gadget when its RX path stalls";
      wantedBy = [ "sysinit.target" ];
      before = [ "sysinit.target" ];
      after = [ "usb-gadget.service" ];
      wants = [ "usb-gadget.service" ];
      unitConfig = {
        DefaultDependencies = false;
        IgnoreOnIsolate = true;
        SurviveFinalKillSignal = true;
      };
      serviceConfig = {
        ExecStart = "${rxGuardBusybox} sh ${rxGuardRuntime}";
        Restart = "always";
        RestartSec = "1s";
      };
    };
  };
}
