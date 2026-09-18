# Host-side artifact + runner builders. Pure function of:
#   - `lib`              — nixpkgs lib.
#   - `hostShellPrelude` — the bash glue shared by every runner
#                          (see lib/host-prelude.nix).
#
# Returns a function `pkgs -> { mkBootFit, mkKexecPayload, mkLiveRootfs,
# mkKexecRunner, mkUsbBootRunner, sg2002OledOverlayDtbo,
# kernelTestBootargs, mkLiveBootargs }`.
#
# Split out of flake.nix so flake.nix stays roughly the size of an
# actual flake.nix and these heavy bash bodies live in a named file.
{ lib
, nanokvm
, hostShellPrelude
,
}: pkgs:
let
  # Select the board DTB for direct FIT boot and kexec payloads. The
  # NB: the DTB is no longer chosen here — every board's
  # `config.sg2002.fdt` is the single source of truth (set by the
  # platform default + the WiFi/OLED/ethernet modules). mkBootFit and
  # mkKexecPayload read it straight off the resolved NixOS config.
  mkFeatureBootargs = { oled ? false }:
    lib.optionals oled [
      "fbcon=font:MINI4x6"
      "fbcon=rotate:1"
    ];

  mkKexecFeatureBootargs = { oled ? false }:
    lib.optionals oled [ "nanokvm.kexec_target_overlay=oled" ]
    ++ mkFeatureBootargs { inherit oled; };


  sg2002OledOverlayDtbo =
    pkgs.runCommand "sg2002-licheerv-nano-oled.dtbo"
      {
        nativeBuildInputs = [ pkgs.dtc ];
      } ''
      dtc -@ -I dts -O dtb -o "$out" ${nanokvm + "/dtb/sg2002-licheerv-nano-oled.dtso"}
    '';

  mkBootFit =
    { profile
    , cfg
    , description
    ,
    }:
    pkgs.sg2002-boot-fit {
      kernel = cfg.config.system.build.kernel;
      # Single source of truth — the board config already resolved which
      # DTB to boot (platform default + WiFi/OLED/ethernet modules).
      fdt = cfg.config.sg2002.fdt;
      initrd = "${cfg.config.system.build.initialRamdisk}/initrd";
      loadAddrs = {
        kernel = "0x80200000";
        initrd = "0x85000000";
      };
      configName = "config-sg2002_licheervnano_sd";
      inherit description;
    };

  mkKexecBootargs =
    { prefix ? [ ]
    , extra ? [ ]
    , usbConsole ? true
    , uartConsole ? "ttyS0"
    ,
    }:
    lib.concatStringsSep " " (prefix
      ++ lib.optional (uartConsole != null) "console=${uartConsole},115200"
      # ttyGS0 LAST when enabled: /dev/console is the last console= entry.
      # Full NFS boots may disable it because closing an unopened gadget
      # console can block PID 1 in gs_close() during switch-root.
      ++ lib.optional usbConsole "console=ttyGS0,115200"
      ++ [
      "earlycon=sbi"
      "ignore_loglevel"
      "panic=10"
      "oops=panic"
      "riscv.fwsz=0x80000"
    ]
      ++ extra);

  oledBootargs = mkFeatureBootargs { oled = true; };

  mkKexecPayload =
    { name
    , cfg
    , rootfsCfg ? cfg
    , oled ? false
    , extraBootargs ? [ ]
    , usbConsole ? true
    , uartConsole ? "ttyS0"
    ,
    }:
    let
      # The OLED DTs deliberately don't set /chosen/bootargs because the
      # direct FIT and kexec paths both provide cmdline params here.
      featureBootargs = mkKexecFeatureBootargs { inherit oled; };
    in
    pkgs.nanokvm-kexec-payload-erofs {
      inherit name;
      kernel = "${cfg.config.system.build.kernel}/Image";
      initrd = "${cfg.config.system.build.initialRamdisk}/initrd";
      dtb = cfg.config.sg2002.fdt;
      dtbo =
        if oled
        then sg2002OledOverlayDtbo
        else null;
      cmdline = mkKexecBootargs {
        inherit uartConsole usbConsole;
        extra = extraBootargs ++ featureBootargs;
      };
    };

  mkLiveRootfs = cfg: pkgs.nanokvm-erofs-rootfs-for cfg.config.system.build.toplevel;

  mkRootfsRuntimeSetup =
    { label
    , rootfsBindIp ? null
    , requireRootfsHostOverride ? false
    ,
    }:
    let
      rootfsHostDefault =
        if rootfsBindIp == null
        then "$nanokvm_host_ip"
        else rootfsBindIp;
      rootfsBindDefault =
        if rootfsBindIp == null
        then ""
        else rootfsBindIp;
    in
    ''
      ${lib.optionalString requireRootfsHostOverride ''
        if [ -z "''${NANOKVM_NBD_ROOTFS_HOST:-}" ]; then
          echo "[${label}] NANOKVM_NBD_ROOTFS_HOST is required for this variant; set it to the host address reachable from the target network" >&2
          echo "[${label}] optionally set NANOKVM_NBD_ROOTFS_BIND to the local address nbd-server should bind" >&2
          exit 1
        fi
      ''}
      rootfs_host="''${NANOKVM_NBD_ROOTFS_HOST:-${rootfsHostDefault}}"
      rootfs_bind="''${NANOKVM_NBD_ROOTFS_BIND:-${rootfsBindDefault}}"
      rootfs_port_request="''${NANOKVM_NBD_ROOTFS_PORT:-auto}"
      rootfs_port="$(choose_tcp_port "$rootfs_port_request")" || exit 1
      nanokvm_port_nbd_rootfs="$rootfs_port"
      rootfs_endpoint="$(nbd_endpoint "$rootfs_bind" "$rootfs_port")"
      echo "[${label}] selected rootfs NBD endpoint candidate: $rootfs_endpoint; target will connect to $rootfs_host:$rootfs_port"
    '';

  mkKexecRunner =
    { name
    , payload
    , rootfs ? null
    , rootfsBindIp ? null
    , requireRootfsHostOverride ? false
    , useRunningDtb ? false
    , applyDtbOverlay ? false
    , loadOnly ? false
    , oled ? false
    ,
    }:
    let
      applyDtbOverlay' = applyDtbOverlay || oled;
      boolFlag = b:
        if b
        then "1"
        else "0";
      # Serve the rootfs nbd-server, killing any orphan bound to the
      # port first. Two flows want different timing:
      #
      #   - First boot from initrd: the rootfs has to be live BEFORE
      #     we send the kexec request because the new kernel's
      #     initrd is the first user. Use `preInject=1`.
      #   - Stage2→stage2 kexec with a NEW rootfs: an OLD nbd-server
      #     is already serving the running rootfs; killing/replacing
      #     it before the source userspace has finished kexec()ing
      #     poisons the running erofs cache. Defer the swap until
      #     after the request is ACK'd and the agent has had time
      #     to load its payload. Use `preInject=0`.
      rootfsService = preInject:
        lib.optionalString (rootfs != null) ''
          start_rootfs_nbd() {
            local rootfs_nbd_config rootfs_nbd_log
            free_tcp_listener usb-kexec "$nanokvm_port_nbd_rootfs" || return 1
            echo "[usb-kexec] serving rootfs ${rootfs} on $rootfs_endpoint"
            rootfs_nbd_config="$(write_nbd_config erofs-rootfs "$rootfs_bind" "$nanokvm_port_nbd_rootfs" rootfs ${rootfs})"
            rootfs_nbd_log="$(mktemp -t nanokvm-rootfs-nbd-XXXXXX.log)"
            nbd-server -C "$rootfs_nbd_config" -d >"$rootfs_nbd_log" 2>&1 &
            rootfs_nbd_pid=$!
            sleep 0.5
            if ! kill -0 "$rootfs_nbd_pid" 2>/dev/null; then
              echo "[usb-kexec] rootfs nbd-server exited early" >&2
              sed -u 's/^/[nbd-rootfs] /' "$rootfs_nbd_log" >&2 || true
              wait "$rootfs_nbd_pid" || true
              return 1
            fi
          }
          ${lib.optionalString preInject "start_rootfs_nbd"}
        '';
      postInjectSwap =
        if rootfs != null
        then ''
          # Give the agent time to: connect /dev/nbd1, mount payload
          # erofs, kexec -c -l (reads ~40 MB of kernel+initrd from NBD
          # at ~20 MB/s), disconnect payload, report, kexec -e. 8 s is
          # generous on a cv1800; the agent typically finishes in 2-4 s
          # but under memory pressure (when prepare-kexec-stage's
          # vmtouch primes got evicted) the bash/glibc reads from
          # /dev/nbd0 cost an extra 0.5-2 s.
          sleep 8
          start_rootfs_nbd || exit 1
          echo "[usb-kexec] rootfs nbd handed off; new kernel's initrd will connect here"
          case "''${NANOKVM_ATTACH:-shell}" in
            shell|"")
              attach_debug_shell_after_reconnect usb-kexec 45 240 || true
              echo "[usb-kexec] shell detached; rootfs NBD is still running. Ctrl-C stops it."
              ;;
            none)
              echo "[usb-kexec] not attaching to target shell; rootfs NBD is running"
              ;;
            *)
              echo "[usb-kexec] invalid NANOKVM_ATTACH=''${NANOKVM_ATTACH}; expected shell or none" >&2
              exit 1
              ;;
          esac
          wait "$rootfs_nbd_pid"
        ''
        else ''
          echo "[usb-kexec] command sent"
          case "''${NANOKVM_ATTACH:-shell}" in
            shell|"") attach_debug_shell_after_reconnect usb-kexec 45 180 || true ;;
            none) sleep 90 ;;
            *)
              echo "[usb-kexec] invalid NANOKVM_ATTACH=''${NANOKVM_ATTACH}; expected shell or none" >&2
              exit 1
              ;;
          esac
        '';
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        gnugrep
        gnused
        inetutils # telnet client for the target busybox telnetd
        iproute2 # ip + ss (latter is used to find orphan nbd-server)
        nbd
        netcat-openbsd
        systemd # networkctl for host-side networkd runtime overrides
      ];
      text = ''
        ${hostShellPrelude}

        payload_nbd_pid=
        rootfs_nbd_pid=
        status_pid=

        cleanup() {
          for pid in "$status_pid" "$payload_nbd_pid" "$rootfs_nbd_pid"; do
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
              kill_process_tree "$pid"
            fi
          done
        }
        trap cleanup EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM

        ${lib.optionalString (rootfs != null) (mkRootfsRuntimeSetup {
          label = "usb-kexec";
          inherit rootfsBindIp requireRootfsHostOverride;
        })}

        configure_host_iface usb-kexec >/dev/null || exit 1

        start_status_sink usb-kexec

        ${rootfsService false}

        payload_nbd_log="$(mktemp -t nanokvm-payload-nbd-XXXXXX.log)"
        echo "[usb-kexec] serving kexec payload ${payload} on $nanokvm_host_ip:$nanokvm_port_nbd_payload"
        nbd-server "$nanokvm_host_ip:$nanokvm_port_nbd_payload" ${payload} -r -n >"$payload_nbd_log" 2>&1 &
        payload_nbd_pid=$!
        sleep 0.5
        if ! kill -0 "$payload_nbd_pid" 2>/dev/null; then
          echo "[usb-kexec] payload nbd-server exited early" >&2
          sed -u 's/^/[nbd-payload] /' "$payload_nbd_log" >&2 || true
          wait "$payload_nbd_pid"
        fi

        target_request="payload_host=$nanokvm_host_ip payload_port=$nanokvm_port_nbd_payload use_running_dtb=${boolFlag useRunningDtb} apply_dtb_overlay=${boolFlag applyDtbOverlay'} load_only=${boolFlag loadOnly}"
        ${lib.optionalString (rootfs != null) ''
          target_request="$target_request rootfs_host=$rootfs_host rootfs_port=$rootfs_port"
        ''}

        echo "[usb-kexec] sending request to $nanokvm_target_ip:$nanokvm_port_kexec"
        kexec_send_request "$target_request" || {
          echo "[usb-kexec] failed to start target kexec agent" >&2
          exit 1
        }

        ${postInjectSwap}
      '';
    };

  mkUsbBootRunner =
    { name
    , fit
    , rootfs ? null
    , bootargs
    , rootfsBindIp ? null
    , requireRootfsHostOverride ? false
    , usbBootTool ? pkgs.sg2002-usb-boot
    , attachPicocom ? false
    , waitForSsh ? false
    , onShellDetachCommand ? null
    ,
    }:
    let
      rootfsService = lib.optionalString (rootfs != null) ''
        start_rootfs_nbd() {
          local attempt max_attempts rootfs_nbd_config rootfs_nbd_log

          cleanup_nanokvm_rootfs_nbd usb-boot || true
          case "$rootfs_port_request" in
            ""|auto|0) max_attempts=20 ;;
            *) max_attempts=1 ;;
          esac

          for attempt in $(seq 1 "$max_attempts"); do
            if [ "$attempt" != 1 ]; then
              rootfs_port="$(choose_tcp_port "$rootfs_port_request")" || return 1
              nanokvm_port_nbd_rootfs="$rootfs_port"
              rootfs_endpoint="$(nbd_endpoint "$rootfs_bind" "$rootfs_port")"
            fi

            if [ "$max_attempts" = 1 ]; then
              free_tcp_listener usb-boot "$rootfs_port" || return 1
              echo "[usb-boot] serving ${rootfs} on $rootfs_endpoint"
            else
              echo "[usb-boot] serving ${rootfs} on $rootfs_endpoint (attempt $attempt/$max_attempts)"
            fi

            rootfs_nbd_config="$(write_nbd_config erofs-rootfs "$rootfs_bind" "$rootfs_port" rootfs ${rootfs})"
            rootfs_nbd_log="$(mktemp -t nanokvm-rootfs-nbd-XXXXXX.log)"
            nbd-server -C "$rootfs_nbd_config" -d >"$rootfs_nbd_log" 2>&1 &
            nbd_pid=$!
            sleep 0.5
            if kill -0 "$nbd_pid" 2>/dev/null; then
              echo "[usb-boot] rootfs NBD endpoint: $rootfs_endpoint; target connects to $rootfs_host:$rootfs_port"
              return 0
            fi

            echo "[usb-boot] nbd-server exited early on $rootfs_endpoint" >&2
            sed -u 's/^/[nbd-rootfs] /' "$rootfs_nbd_log" >&2 || true
            wait "$nbd_pid" 2>/dev/null || true
            nbd_pid=
            [ "$max_attempts" != 1 ] || return 1
            sleep 0.1
          done

          echo "[usb-boot] unable to start rootfs nbd-server after $max_attempts attempts" >&2
          return 1
        }

        start_rootfs_nbd || exit 1
      '';
      sshWait = lib.optionalString waitForSsh ''
        echo "[usb-boot] waiting for SSH on root@$nanokvm_target_ip..."
        ssh_ready=0
        for _ in $(seq 1 180); do
          if timeout 1 bash -c ":</dev/tcp/$nanokvm_target_ip/22" 2>/dev/null; then
            ssh_ready=1
            break
          fi
          if [ -n "''${nbd_pid:-}" ] && ! kill -0 "$nbd_pid" 2>/dev/null; then
            echo "[usb-boot] nbd-server exited while the device was booting" >&2
            wait "$nbd_pid"
          fi
          sleep 1
        done
        if [ "$ssh_ready" = 1 ]; then
          echo "[usb-boot] SSH is up: ssh root@$nanokvm_target_ip (password: nixos)"
          echo "[usb-boot] NanoKVM web app target: http://$nanokvm_target_ip/"
        else
          echo "[usb-boot] SSH did not answer yet; keeping NBD server running for inspection"
        fi
      '';
      picocomTail = lib.optionalString attachPicocom ''
        before_acm="$(list_acm | sort)"
        acm="$(wait_acm "$before_acm")" || {
          echo "[usb-boot] timed out waiting for /dev/ttyACM*" >&2
          exit 1
        }
        log="$(mktemp -t nanokvm-usb-boot-XXXXXX.log)"
        echo "[usb-boot] attaching picocom to $acm"
        echo "[usb-boot] full session is also being written to $log"
        picocom --baud 115200 --noinit --logfile "$log" "$acm"
      '';
      wait = lib.optionalString (rootfs != null) ''
        echo "[usb-boot] leave this process running; Ctrl-C stops the NBD backing store"
        wait "$nbd_pid"
      '';
      shellTail = ''
        attach_debug_shell usb-boot 240 || true
        ${lib.optionalString (rootfs != null) ''
          case "''${NANOKVM_ON_DETACH:-hold}" in
            hold|"")
              echo "[usb-boot] shell detached; rootfs NBD is still running. Ctrl-C stops it."
              wait "$nbd_pid"
              ;;
            kexec)
              ${if onShellDetachCommand != null then ''
                echo "[usb-boot] shell detached; kexecing target to the next image..."
                ${onShellDetachCommand}
              '' else ''
                echo "[usb-boot] NANOKVM_ON_DETACH=kexec is not available for this runner" >&2
                wait "$nbd_pid"
              ''}
              ;;
            exit)
              echo "[usb-boot] shell detached; stopping rootfs NBD"
              exit 0
              ;;
            *)
              echo "[usb-boot] invalid NANOKVM_ON_DETACH=''${NANOKVM_ON_DETACH}; expected hold, kexec, or exit" >&2
              exit 1
              ;;
          esac
        ''}
      '';
      attachTail = ''
        case "''${NANOKVM_ATTACH:-shell}" in
          shell|"")
            ${shellTail}
            ;;
          picocom)
            ${if attachPicocom
              then ''
                ${picocomTail}
                ${wait}
              ''
              else ''
                echo "[usb-boot] NANOKVM_ATTACH=picocom is only available for ACM/debug variants" >&2
                exit 1
              ''}
            ;;
          none)
            ${wait}
            ;;
          *)
            echo "[usb-boot] invalid NANOKVM_ATTACH=''${NANOKVM_ATTACH}; expected shell, picocom, or none" >&2
            exit 1
            ;;
        esac
      '';
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        android-tools
        bash
        coreutils
        gnugrep
        inetutils # telnet client for the target busybox telnetd
        iproute2
        nbd
        netcat-openbsd
        picocom
        systemd # networkctl for host-side networkd runtime overrides
      ];
      text = ''
        ${hostShellPrelude}

        nbd_pid=
        status_pid=

        cleanup() {
          for pid in "$status_pid" "$nbd_pid"; do
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
              kill_process_tree "$pid"
            fi
          done
        }
        trap cleanup EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM

        bootargs=${lib.escapeShellArg bootargs}
        case "''${1:-}" in
          -h|--help)
            exec ${usbBootTool}/bin/usb-boot-mainline \
              --bootargs "$bootargs" \
              ${fit} "$@"
            ;;
        esac

        ${lib.optionalString (rootfs != null) ''
          ${mkRootfsRuntimeSetup {
            label = "usb-boot";
            inherit rootfsBindIp requireRootfsHostOverride;
          }}
          ${rootfsService}

          bootargs="$bootargs nanokvm.nbd_rootfs_host=$rootfs_host nanokvm.nbd_rootfs_port=$rootfs_port"
        ''}

        ${usbBootTool}/bin/usb-boot-mainline \
          --bootargs "$bootargs" \
          ${fit} "$@"

        configure_host_iface usb-boot >/dev/null || exit 1

        start_status_sink usb-boot

        ${sshWait}

        ${attachTail}

      '';
    };

  kernelTestBootargs = mkKexecBootargs { };

  # ---------------------------------------------------------------------
  # NFS-live host-side pieces.
  #
  # The NBD runners above ship a prebuilt erofs rootfs per generation;
  # the NFS runners rely on the dev host's *kernel* nfsd instead: it
  # exports /nix/store read-only (on trex via /export/nix-store — see
  # the netboot-server profile in ../nixos-config; the USB-link CIDR
  # 10.55.0.0/24 must be in the export). The target mounts it
  # kernel-direct from its initrd and puts a tmpfs overlay on top, so
  # a rebuild on the host is bootable immediately with no image step
  # in between, the target stays completely stateless, and the runner
  # has no server process to babysit.
  # ---------------------------------------------------------------------

  # Check the local NFSv4 pseudo-root before touching the board. A listener on
  # port 2049 is not enough: the USB CIDR needs both the fsid=0 pseudo-root and
  # the requested child export, read-only. This catches the exact failure mode
  # where PUTROOTFH is denied even though /export/nix-store is exported.
  nfsLocalExportCheck = label: ''
    check_local_nfs_exports() {
      [ "$nfs_server" = "$nanokvm_host_ip" ] || return 0

      local exports physical_export
      exports="$(as_root exportfs -v 2>/dev/null)" || {
        echo "[${label}] ERROR: unable to inspect the local NFS exports" >&2
        return 1
      }
      physical_export="/export''${nfs_export%/}"
      [ "$physical_export" != "/export" ] || physical_export=/export

      export_allows_usb_ro() {
        local wanted="$1" require_fsid="$2"
        printf '%s\n' "$exports" | awk \
          -v wanted="$wanted" \
          -v client="10.55.0.0/24" \
          -v require_fsid="$require_fsid" '
            /^\// { current = $1 }
            current == wanted && index($0, client) > 0 &&
              $0 ~ /(^|[,(])ro([,)])/ &&
              (!require_fsid || index($0, "fsid=0") > 0) { found = 1 }
            END { exit(found ? 0 : 1) }
          '
      }

      if ! export_allows_usb_ro /export 1; then
        echo "[${label}] ERROR: 10.55.0.0/24 lacks a read-only fsid=0 /export pseudo-root" >&2
        return 1
      fi
      if ! export_allows_usb_ro "$physical_export" 0; then
        echo "[${label}] ERROR: 10.55.0.0/24 lacks read-only export $physical_export" >&2
        return 1
      fi
      echo "[${label}] verified local NFSv4 exports for 10.55.0.0/24 ($physical_export)"
    }

    check_local_nfs_exports || exit 1
  '';

  # Soft reachability check run once the USB link is up: the host nfsd should
  # answer on 2049. Remote servers cannot be exportfs-inspected, so the target's
  # initrd mount remains authoritative there.
  nfsServerCheck = label: ''
    # $1 belongs to the child bash; keeping this single-quoted prevents the
    # server value from being reparsed as shell code.
    # shellcheck disable=SC2016
    if timeout 2 bash -c ':</dev/tcp/$1/2049' bash "$nfs_server" 2>/dev/null; then
      echo "[${label}] NFS server answers on $nfs_server:2049"
    else
      echo "[${label}] WARNING: nothing on $nfs_server:2049 — the target will hang mounting /nix/store." >&2
      if [ "$nfs_server" = "$nanokvm_host_ip" ]; then
        echo "[${label}] The USB client needs both 10.55.0.0/24:/export (fsid=0) and 10.55.0.0/24:/export/nix-store exported read-only." >&2
      fi
    fi
  '';

  mkNfsUsbBootRunner =
    { name
    , fit
    , bootargs
    , nfsServer
    , nfsExport
    , usbBootTool ? pkgs.sg2002-usb-boot
    , waitForSsh ? false
    , onShellDetachCommand ? null
    ,
    }:
    let
      sshWait = lib.optionalString waitForSsh ''
        echo "[usb-boot] waiting for SSH on root@$nanokvm_target_ip..."
        ssh_ready=0
        for _ in $(seq 1 180); do
          if timeout 1 bash -c ":</dev/tcp/$nanokvm_target_ip/22" 2>/dev/null; then
            ssh_ready=1
            break
          fi
          if cv181x_rom_present; then
            echo "[usb-boot] target returned to the CV181x BootROM while waiting for SSH" >&2
            exit 1
          fi
          sleep 1
        done
        if [ "$ssh_ready" = 1 ]; then
          echo "[usb-boot] SSH is up: ssh -o StrictHostKeyChecking=accept-new root@$nanokvm_target_ip (password: nixos)"
        else
          echo "[usb-boot] SSH did not answer" >&2
          exit 1
        fi
      '';
      # Nothing to babysit after detach: the store is served by the
      # host's kernel nfsd, independent of this process.
      detachNote = ''
        echo "[usb-boot] shell detached; the board keeps running (host kernel nfsd serves /nix/store). This runner exits."
      '';
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        android-tools
        bash
        coreutils
        gawk # nfsLocalExportCheck parses exportfs output
        gnugrep
        inetutils # telnet client for the target busybox telnetd
        iproute2
        netcat-openbsd
        nfs-utils
        systemd # networkctl for host-side networkd runtime overrides
      ];
      text = ''
        ${hostShellPrelude}

        status_pid=

        cleanup() {
          if [ -n "$status_pid" ] && kill -0 "$status_pid" 2>/dev/null; then
            kill_process_tree "$status_pid"
          fi
        }
        trap cleanup EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM

        bootargs=${lib.escapeShellArg bootargs}
        nfs_server=${lib.escapeShellArg nfsServer}
        nfs_export=${lib.escapeShellArg nfsExport}

        if [ -n "''${NANOKVM_NFS_SERVER:-}" ]; then
          case "$NANOKVM_NFS_SERVER" in
            *[[:space:]]*)
              echo "[usb-boot] NANOKVM_NFS_SERVER must not contain whitespace" >&2
              exit 1
              ;;
          esac
          nfs_server="$NANOKVM_NFS_SERVER"
          bootargs="$bootargs nanokvm.nfs_server=$nfs_server"
        fi
        if [ -n "''${NANOKVM_NFS_EXPORT:-}" ]; then
          case "$NANOKVM_NFS_EXPORT" in
            /*) ;;
            *)
              echo "[usb-boot] NANOKVM_NFS_EXPORT must be an absolute NFSv4 pseudo-path" >&2
              exit 1
              ;;
          esac
          case "$NANOKVM_NFS_EXPORT" in
            *[[:space:]]*)
              echo "[usb-boot] NANOKVM_NFS_EXPORT must not contain whitespace" >&2
              exit 1
              ;;
          esac
          nfs_export="$NANOKVM_NFS_EXPORT"
          bootargs="$bootargs nanokvm.nfs_export=$nfs_export"
        fi
        if [ "''${NANOKVM_ON_DETACH:-hold}" = kexec ] \
            && { [ -n "''${NANOKVM_NFS_SERVER:-}" ] || [ -n "''${NANOKVM_NFS_EXPORT:-}" ]; }; then
          echo "[usb-boot] runtime NFS overrides do not survive detach-to-kexec; bake the values into the board config or choose NANOKVM_ON_DETACH=hold" >&2
          exit 1
        fi
        case "''${1:-}" in
          -h|--help)
            exec ${usbBootTool}/bin/usb-boot-mainline \
              --bootargs "$bootargs" \
              ${fit} "$@"
            ;;
        esac

        ${nfsLocalExportCheck "usb-boot"}

        ${usbBootTool}/bin/usb-boot-mainline \
          --bootargs "$bootargs" \
          ${fit} "$@"

        configure_host_iface usb-boot >/dev/null || exit 1

        ${nfsServerCheck "usb-boot"}

        start_status_sink usb-boot

        ${sshWait}

        case "''${NANOKVM_ATTACH:-shell}" in
          shell|"")
            attach_debug_shell usb-boot 240 || true
            case "''${NANOKVM_ON_DETACH:-hold}" in
              hold|"")
                ${detachNote}
                ;;
              kexec)
                ${if onShellDetachCommand != null then ''
                  echo "[usb-boot] shell detached; kexecing target to the next image..."
                  ${onShellDetachCommand}
                '' else ''
                  echo "[usb-boot] NANOKVM_ON_DETACH=kexec is not available for this runner" >&2
                  exit 1
                ''}
                ;;
              exit)
                echo "[usb-boot] shell detached; exiting"
                ;;
              *)
                echo "[usb-boot] invalid NANOKVM_ON_DETACH=''${NANOKVM_ON_DETACH}; expected hold, kexec, or exit" >&2
                exit 1
                ;;
            esac
            ;;
          none)
            ;;
          *)
            echo "[usb-boot] invalid NANOKVM_ATTACH=''${NANOKVM_ATTACH}; expected shell or none" >&2
            exit 1
            ;;
        esac
      '';
    };

  # Payload-only kexec runner for the NFS live profile: the store is
  # served by the host's kernel nfsd (independent of any runner), so
  # this is mkKexecRunner minus the rootfs NBD dance. The payload
  # itself still travels over NBD — it's tiny and the target agent
  # already speaks it.
  mkNfsKexecRunner =
    { name
    , payload
    , nfsServer
    , nfsExport
    , useRunningDtb ? true
    ,
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        gawk # nfsLocalExportCheck parses exportfs output
        gnugrep
        inetutils
        iproute2
        nbd
        netcat-openbsd
        nfs-utils
        systemd
      ];
      text = ''
        ${hostShellPrelude}

        payload_nbd_pid=
        status_pid=

        cleanup() {
          for pid in "$status_pid" "$payload_nbd_pid"; do
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
              kill_process_tree "$pid"
            fi
          done
        }
        trap cleanup EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM

        nfs_server=${lib.escapeShellArg nfsServer}
        nfs_export=${lib.escapeShellArg nfsExport}

        ${nfsLocalExportCheck "usb-kexec"}

        configure_host_iface usb-kexec >/dev/null || exit 1

        ${nfsServerCheck "usb-kexec"}

        start_status_sink usb-kexec

        payload_nbd_log="$(mktemp -t nanokvm-payload-nbd-XXXXXX.log)"
        echo "[usb-kexec] serving kexec payload ${payload} on $nanokvm_host_ip:$nanokvm_port_nbd_payload"
        nbd-server "$nanokvm_host_ip:$nanokvm_port_nbd_payload" ${payload} -r -n >"$payload_nbd_log" 2>&1 &
        payload_nbd_pid=$!
        sleep 0.5
        if ! kill -0 "$payload_nbd_pid" 2>/dev/null; then
          echo "[usb-kexec] payload nbd-server exited early" >&2
          sed -u 's/^/[nbd-payload] /' "$payload_nbd_log" >&2 || true
          wait "$payload_nbd_pid"
        fi

        target_request="payload_host=$nanokvm_host_ip payload_port=$nanokvm_port_nbd_payload use_running_dtb=${if useRunningDtb then "1" else "0"} apply_dtb_overlay=0 load_only=0"

        echo "[usb-kexec] sending request to $nanokvm_target_ip:$nanokvm_port_kexec"
        kexec_send_request "$target_request" || {
          echo "[usb-kexec] failed to start target kexec agent" >&2
          exit 1
        }

        echo "[usb-kexec] command sent"
        case "''${NANOKVM_ATTACH:-shell}" in
          shell|"") attach_debug_shell_after_reconnect usb-kexec 45 240 || true ;;
          none) sleep 90 ;;
          *)
            echo "[usb-kexec] invalid NANOKVM_ATTACH=''${NANOKVM_ATTACH}; expected shell or none" >&2
            exit 1
            ;;
        esac
      '';
    };


  mkLiveBootargs =
    { cfg
    , extra ? [ ]
    , oled ? false
    , usbConsole ? true
    , uartConsole ? "ttyS0"
    ,
    }:
    mkKexecBootargs {
      inherit uartConsole usbConsole;
      extra =
        [ "init=${cfg.config.system.build.toplevel}/init" ]
        ++ extra
        ++ mkFeatureBootargs { inherit oled; };
    };
in
{
  inherit
    mkBootFit
    mkKexecPayload
    mkLiveRootfs
    mkKexecRunner
    mkUsbBootRunner
    mkNfsUsbBootRunner
    mkNfsKexecRunner
    sg2002OledOverlayDtbo
    mkFeatureBootargs
    oledBootargs
    kernelTestBootargs
    mkKexecBootargs
    mkLiveBootargs
    ;
}
