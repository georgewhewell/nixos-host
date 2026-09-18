# Target-side kexec control plane:
#   - one-shot accepted-socket on $nanokvm_target_ip:2325
#   - request parser (key=value over the accepted connection)
#   - agent that pulls the payload erofs over /dev/nbd1 and kexec's
#   - boot-time `prepare-kexec-stage` that vmtouch-primes the agent's
#     binary closure so the agent survives the host swapping the
#     rootfs nbd-server mid-flight.
#
# Extracted out of `modules/usb-control.nix`. Gated by
# `nanokvm.usbControl.kexec.enable` (default on mainline, off on vendor;
# see usb-control.nix for the option declaration).
{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.nanokvm.usbControl;

  targetLib = import ./target-script-lib.nix { inherit lib pkgs config; };
  inherit (targetLib) targetTools kernelIsMainline mkTargetScript protocol;

  # Everything the kexec agent might touch at runtime — drives the
  # vmtouch prime list.
  kexecStageRoots = targetTools;

  kexecAgent = mkTargetScript "nanokvm-kexec-agent" ''
    payload_host="''${1:-$nanokvm_host_ip}"
    payload_port="''${2:-$nanokvm_port_nbd_payload}"

    # Status pushes always go to the host on the protocol-pinned sink
    # ($nanokvm_host_ip:$nanokvm_port_status). The request grammar
    # used to accept status_host/status_port but the values were never
    # threaded through nanokvm_push_status — they were a lie. If we
    # later want to redirect status, do it once via protocol.nix, not
    # per-request.

    use_running_dtb="''${NANOKVM_USE_RUNNING_DTB:-0}"
    apply_dtb_overlay="''${NANOKVM_APPLY_DTB_OVERLAY:-0}"
    load_only="''${NANOKVM_LOAD_ONLY:-0}"
    rootfs_host="''${NANOKVM_ROOTFS_HOST:-}"
    rootfs_port="''${NANOKVM_ROOTFS_PORT:-}"

    payload_dev=/dev/nbd1
    payload_mount=/run/kexec-payload
    overlayed_dtb=/run/kexec-overlay.dtb
    kexec_log=/run/kexec-load.log

    report() {
      {
        echo "===== nanokvm kexec ====="
        echo "$@"
        echo "--- cmdline"
        cat /proc/cmdline 2>&1 || true
        echo "--- ip"
        if iface="$(nanokvm_find_iface 2>/dev/null)"; then
          ip addr show "$iface" 2>&1 || true
        else
          ip addr show 2>&1 || true
        fi
        echo "--- nbd"
        ls -l /dev/nbd0 /dev/nbd1 /sys/block/nbd0/pid /sys/block/nbd1/pid 2>&1 || true
        cat /sys/block/nbd0/pid /sys/block/nbd1/pid 2>&1 || true
        echo "--- mounts"
        cat /proc/mounts 2>&1 || true
        echo "--- memory"
        df -h /dev/shm /run 2>&1 || true
        if [ -s "$kexec_log" ]; then
          echo "--- kexec load log"
          cat "$kexec_log" 2>&1 || true
        fi
        echo "===== end nanokvm kexec ====="
      } | nanokvm_push_status
    }

    disconnect_payload() {
      umount "$payload_mount" >/dev/null 2>&1 || true
      if nbd-client -c "$payload_dev" >/dev/null 2>&1; then
        nbd-client -d "$payload_dev" >/dev/null 2>&1 || true
      fi
    }

    # Reset NBD client state we own. /dev/nbd0 may back the live root
    # in stage-2 (mounted at /nix/.ro-store) — leave it alone in that
    # case; the kernel will tear it down on kexec -e.
    reset_nbd_state() {
      if command -v systemctl >/dev/null 2>&1; then
        systemctl stop nanokvm-debug-nbd.service >/dev/null 2>&1 || true
      fi
      umount /mnt/nbd-root >/dev/null 2>&1 || true
      disconnect_payload

      if ! grep -q '^/dev/nbd0 ' /proc/mounts 2>/dev/null; then
        if nbd-client -c /dev/nbd0 >/dev/null 2>&1; then
          nbd-client -d /dev/nbd0 >/dev/null 2>&1 || true
        fi
      fi

      sync
    }

    report "agent starting"
    if iface="$(nanokvm_find_iface 2>/dev/null)"; then
      ip link set "$iface" up || true
      ip addr replace "$nanokvm_target_ip/$nanokvm_prefix" dev "$iface" || true
    fi

    reset_nbd_state

    [ -e "$payload_dev" ] || mknod "$payload_dev" b 43 1

    report "connecting payload nbd"
    nbd-client -R -n -p --systemd-mark "$payload_host" "$payload_port" "$payload_dev" &
    client=$!

    for i in $(seq 1 300); do
      if nbd-client -c "$payload_dev" >/dev/null 2>&1; then
        break
      fi
      if ! kill -0 "$client" 2>/dev/null; then
        wait "$client" 2>/dev/null || true
        report "payload nbd client exited before connect"
        exit 1
      fi
      if [ "$i" = 1 ] || [ "$i" = 300 ]; then
        report "waiting for payload nbd $i/300"
      fi
      sleep 0.1
    done

    if ! nbd-client -c "$payload_dev" >/dev/null 2>&1; then
      report "payload nbd failed to connect"
      exit 1
    fi

    mkdir -p "$payload_mount"
    mount -t erofs -o ro "$payload_dev" "$payload_mount"
    cmdline="$(cat "$payload_mount/cmdline")"
    if [ -n "$rootfs_host" ]; then
      cmdline="$cmdline nanokvm.nbd_rootfs_host=$rootfs_host"
    fi
    if [ -n "$rootfs_port" ]; then
      cmdline="$cmdline nanokvm.nbd_rootfs_port=$rootfs_port"
    fi

    payload_dtb="$payload_mount/dtb"
    if [ "$use_running_dtb" = 1 ] && [ -r /sys/firmware/fdt ]; then
      payload_dtb=/sys/firmware/fdt
    fi

    if [ "$apply_dtb_overlay" = 1 ]; then
      if [ ! -r /sys/firmware/fdt ]; then
        report "running FDT is unavailable"
        exit 1
      fi
      if [ ! -r "$payload_mount/overlay.dtbo" ]; then
        report "DT overlay is missing from kexec payload"
        exit 1
      fi
      report "applying DT overlay to running FDT"
      rm -f "$overlayed_dtb" "$kexec_log"
      if ! fdtoverlay -i /sys/firmware/fdt -o "$overlayed_dtb" \
        "$payload_mount/overlay.dtbo" >"$kexec_log" 2>&1
      then
        report "DT overlay failed"
        exit 1
      fi
      payload_dtb="$overlayed_dtb"
      report "DT overlay applied"
    fi

    report "loading kexec payload: $cmdline"
    rm -f "$kexec_log"
    # `kexec -c -l` (legacy kexec_load syscall) copies kernel + initrd
    # into kernel-reserved pages immediately, so we can release the
    # EROFS mount and the NBD link as soon as it returns.
    if ! kexec -c -l "$payload_mount/Image" \
      --initrd="$payload_mount/initrd" \
      --dtb="$payload_dtb" \
      --append="$cmdline" \
      >"$kexec_log" 2>&1
    then
      report "kexec load failed"
      exit 1
    fi

    # Detach the payload NBD before kexec -e. We used to also
    # `echo 3 > /proc/sys/vm/drop_caches` here, but that defeats
    # prepare-kexec-stage's page-cache prime — the `report` calls
    # below (and any bash/glibc pages mmap'd lazily) would then have
    # to re-fault from /dev/nbd0 right as the rootfs server may be
    # mid-swap. kexec -c -l already reserved its destination buffer
    # so dropping page cache after that point doesn't help the actual
    # kexec syscall.
    disconnect_payload
    sync

    if [ "$load_only" = 1 ]; then
      report "load-only requested; kexec payload loaded but not executed"
      exit 0
    fi

    report "executing kexec"
    sync
    kexec -e
  '';

  kexecRequest = mkTargetScript "nanokvm-kexec-request" ''
    payload_host="$nanokvm_host_ip"
    payload_port="$nanokvm_port_nbd_payload"
    use_running_dtb=0
    apply_dtb_overlay=0
    load_only=0
    rootfs_host=
    rootfs_port=

    fail() { printf 'ERR %s\n' "$*"; exit 64; }
    valid_bool() { [ "$1" = 0 ] || [ "$1" = 1 ]; }
    valid_port() {
      case "$1" in
        ""|*[!0-9]*) return 1 ;;
      esac
      [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
    }
    valid_ipv4() {
      case "$1" in
        ""|*[!0-9.]*) return 1 ;;
      esac
      return 0
    }

    line=
    IFS= read -r line || true

    # Treat an empty request line as a probe (nc -z, port-scan, etc.)
    # rather than launching the agent with all defaults. Otherwise a
    # plain `wait_tcp` would silently fire off a no-op kexec attempt.
    [ -n "$line" ] || fail "empty request"

    for item in $line; do
      case "$item" in
        *=*) ;;
        *) fail "malformed token: $item" ;;
      esac
      key="''${item%%=*}"
      value="''${item#*=}"
      case "$key" in
        payload_host) payload_host="$value" ;;
        payload_port) payload_port="$value" ;;
        use_running_dtb) use_running_dtb="$value" ;;
        apply_dtb_overlay) apply_dtb_overlay="$value" ;;
        load_only) load_only="$value" ;;
        rootfs_host) rootfs_host="$value" ;;
        rootfs_port) rootfs_port="$value" ;;
        *) fail "unknown key: $key" ;;
      esac
    done

    valid_ipv4 "$payload_host"      || fail "invalid payload_host: $payload_host"
    valid_port "$payload_port"      || fail "invalid payload_port: $payload_port"
    valid_bool "$use_running_dtb"   || fail "invalid use_running_dtb: $use_running_dtb"
    valid_bool "$apply_dtb_overlay" || fail "invalid apply_dtb_overlay: $apply_dtb_overlay"
    valid_bool "$load_only"         || fail "invalid load_only: $load_only"
    if [ -n "$rootfs_host" ]; then
      valid_ipv4 "$rootfs_host" || fail "invalid rootfs_host: $rootfs_host"
    fi
    if [ -n "$rootfs_port" ]; then
      valid_port "$rootfs_port" || fail "invalid rootfs_port: $rootfs_port"
    fi

    printf 'OK starting nanokvm-kexec-agent\n'

    export NANOKVM_USE_RUNNING_DTB="$use_running_dtb"
    export NANOKVM_APPLY_DTB_OVERLAY="$apply_dtb_overlay"
    export NANOKVM_LOAD_ONLY="$load_only"
    export NANOKVM_ROOTFS_HOST="$rootfs_host"
    export NANOKVM_ROOTFS_PORT="$rootfs_port"

    exec </dev/null >>/run/nanokvm-kexec-agent.log 2>&1
    echo "request: $line"
    exec ${kexecAgent} "$payload_host" "$payload_port"
  '';

  controlSocket = {
    description = "NanoKVM kexec control socket";
    wantedBy = [ "sockets.target" ];
    # Bind to the USB gadget address only. The socket used to listen
    # on 0.0.0.0; in stage 2 the wifi variant joins the LAN, and a
    # wildcard bind there made the kexec endpoint reachable from any
    # interface — unauthenticated, root-equivalent.
    listenStreams = [ "${protocol.targetIp}:${toString protocol.ports.kexecCtrl}" ];
    socketConfig = {
      Accept = true;
      MaxConnections = 1;
      # The gadget iface may not have its IP assigned yet when
      # systemd opens the socket (configureUsbNetwork.service races
      # with sockets.target); FreeBind lets the bind() succeed
      # against an address the kernel doesn't yet have. We rely on
      # the per-iface firewall (see usb0 allowedTCPPorts below) to
      # keep this from being reachable on the wrong interface.
      FreeBind = true;
    };
  };

  # Closure of every store path the kexec agent might touch — kexec
  # agent + request scripts plus their transitive deps (bash, busybox,
  # kexec-tools, nbd-client-minimal, dtc, glibc, …). ~12 paths on this
  # board.
  kexecStageClosure = pkgs.closureInfo {
    rootPaths = [ kexecAgent kexecRequest ] ++ kexecStageRoots;
  };

  # T7: pack the closure into a small EROFS image. At boot we copy
  # this blob to a tmpfs file at /run/kexec-stage.erofs and loop-mount
  # it at /run/kexec-stage. The agent service then runs inside a
  # mount namespace where /nix/store is bind-mounted from
  # /run/kexec-stage/nix/store — so every binary the agent execs
  # comes from the tmpfs-backed loop device, never the NBD-backed
  # real /nix/store. The agent survives the host-side rootfs nbd
  # swap and any memory-pressure-driven eviction.
  #
  # mkfs.erofs runs on the build host (buildPackages). lz4hc keeps the
  # image ~10–15 MB compressed from ~36 MB uncompressed — small enough
  # to cp into the cv1800's 216 MB without OOM (zramSwap covers the
  # peak), and immutable so the loop device's reads are predictable.
  kexecMicroEnv =
    pkgs.runCommand "nanokvm-kexec-micro-env.erofs"
      {
        nativeBuildInputs = [ pkgs.buildPackages.erofs-utils ];
      } ''
      mkdir -p root/nix/store
      while IFS= read -r p; do
        cp -a "$p" root/nix/store/
      done < ${kexecStageClosure}/store-paths
      mkfs.erofs -z lz4hc "$out" root
    '';

  # T7 implementation: copy the immutable micro-env blob to /run
  # (tmpfs), loop-mount it at /run/kexec-stage, signal ready. The
  # blob lives in /nix/store at rest (NBD-backed, cheap) — once
  # cp'd to /run we have a self-contained kexec environment whose
  # backing pages can't be evicted to NBD-land.
  #
  # Idempotent: re-runs are a no-op once the flag exists.
  prepareKexecStage = pkgs.writeShellScript "prepare-kexec-stage" ''
    set -eu
    flag=/run/kexec-stage.ready
    if [ -e "$flag" ]; then exit 0; fi
    mkdir -p /run/kexec-stage
    # Copy the EROFS image into tmpfs. After this point /nix/store
    # can disappear without breaking the agent.
    ${pkgs.coreutils}/bin/cp ${kexecMicroEnv} /run/kexec-stage.erofs
    # Loop-mount the tmpfs-backed file. -o loop creates the loop
    # device on demand; -o ro because EROFS is read-only anyway.
    ${pkgs.util-linux}/bin/mount -t erofs -o ro,loop \
      /run/kexec-stage.erofs /run/kexec-stage
    size=$(${pkgs.coreutils}/bin/stat -c%s /run/kexec-stage.erofs)
    printf 'mounted=erofs blob_bytes=%s source=%s\n' \
      "$size" '${kexecMicroEnv}' > "$flag"
  '';

  prepareKexecService = {
    description = "Stage kexec agent EROFS for NBD-independent operation";
    unitConfig = {
      DefaultDependencies = false;
      # If something writes to /run before us we still need our
      # subdirectory created cleanly.
      RequiresMountsFor = "/run";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = prepareKexecStage;
      # Tear down at shutdown so logs are clean.
      ExecStop = pkgs.writeShellScript "prepare-kexec-stage-stop" ''
        ${pkgs.util-linux}/bin/umount /run/kexec-stage 2>/dev/null || true
        ${pkgs.coreutils}/bin/rm -f /run/kexec-stage.ready \
          /run/kexec-stage.erofs 2>/dev/null || true
      '';
    };
  };

  # Base service definition. Stage 2 adds the prepare-kexec-stage
  # dependency + the BindReadOnlyPaths overlay (see
  # `controlServiceStage2`). Initrd uses this verbatim — there's no
  # NBD-backed /nix/store in the initrd, so the agent can run
  # directly out of initramfs paths.
  controlServiceCommon = {
    description = "Handle one NanoKVM kexec request";
    serviceConfig = {
      ExecStart = kexecRequest;
      StandardInput = "socket";
      StandardOutput = "socket";
      StandardError = "journal";
    };
  };

  controlServiceStage2 = lib.recursiveUpdate controlServiceCommon {
    unitConfig = {
      Requires = [ "prepare-kexec-stage.service" ];
      After = [ "prepare-kexec-stage.service" ];
      # Hard guard: don't even try to start the agent if the
      # micro-env isn't mounted. Otherwise the BindReadOnlyPaths
      # below would fail to set up, leaving systemd to log a
      # confusing "Failed to load connection service unit" error.
      ConditionPathExists = "/run/kexec-stage.ready";
    };
    serviceConfig = {
      # Inside the service's mount namespace, /nix/store points at
      # the micro-env EROFS. The kexec agent + every binary it
      # exec()s come from the tmpfs-backed loop device, immune to
      # /dev/nbd0 going away.
      PrivateMounts = true;
      BindReadOnlyPaths = [ "/run/kexec-stage/nix/store:/nix/store" ];
    };
  };
in
{
  # `nanokvm.usbControl.kexec.enable` is declared in usb-control.nix
  # (the umbrella) so callers see the option even when this file isn't
  # in the import set. We just consume it here.

  config = lib.mkMerge [
    {
      # Build artifacts: expose the agent and request scripts so
      # other tooling can reach them.
      system.build.nanokvmKexecAgent = kexecAgent;
      system.build.nanokvmKexecRequest = kexecRequest;
    }

    (lib.mkIf (cfg.initrd.enable && cfg.kexec.enable) {
      boot.initrd.systemd = {
        services."usb-kexec-control@" =
          controlServiceCommon
          // {
            after = [ "usb-debug-network.service" "systemd-networkd.service" ];
            wants = [ "usb-debug-network.service" "systemd-networkd.service" ];
          };
        sockets."usb-kexec-control" = controlSocket;
        storePaths = [
          kexecAgent
          kexecRequest
          pkgs.dtc
          pkgs.kexec-tools
          pkgs.nbd-client-minimal
        ];
      };
    })

    (lib.mkIf (cfg.stage2.enable && cfg.kexec.enable) {
      networking.firewall.interfaces.usb0.allowedTCPPorts = [
        protocol.ports.kexecCtrl
      ];

      systemd.services."prepare-kexec-stage" =
        prepareKexecService
        // {
          wantedBy = [ "sysinit.target" ];
          before = [ "sockets.target" "usb-kexec-control.socket" ];
        };

      systemd.services."usb-kexec-control@" =
        controlServiceStage2
        // {
          after = [ "network-online.target" "prepare-kexec-stage.service" ];
          wants = [ "network-online.target" ];
        };

      systemd.sockets."usb-kexec-control" = controlSocket;

      environment.systemPackages = [
        pkgs.kexec-tools
        pkgs.nbd-client-minimal
      ];
    })
  ];
}
