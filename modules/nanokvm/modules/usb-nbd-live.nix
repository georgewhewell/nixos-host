# NBD-backed live root for the NanoKVM. The Nix store lives on
# `/dev/nbd0`, served by the host runner over USB ECM by default.
# Override `nanokvm.nbdLive.host` to point at a different transport
# (e.g. wlan0's LAN gateway) for diagnostics where USB-ECM throughput
# is the suspected bottleneck.
#
# Pairs with `./usb-control.nix`, which provides the kexec control
# socket, debug shell, and networkd config in both initrd and stage 2.
{ config
, lib
, pkgs
, ...
}:
let
  protocol = import ../lib/protocol.nix;
  nbdDevice = "/dev/nbd0";
  rootFsTarget = "sysroot-nix-.ro\\x2dstore.mount";
  nbdHost = config.nanokvm.nbdLive.host;
  nbdPort = config.nanokvm.nbdLive.port;
  nbdStaticIface = config.nanokvm.nbdLive.staticIface;
  # Keep initrd helper binaries on the same systemd package as PID 1. This
  # matters when a platform supplies a patched switch-root implementation.
  systemdPackage = config.systemd.package;
  nbdClient = "${pkgs.nbd-client-minimal}/bin/nbd-client";

  targetTools = [ pkgs.busybox ];

  # When a static-iface bring-up is configured, the script honors the
  # configured mac/ip/prefix rather than always taking them from
  # protocol.nix. The option submodule advertised this; we now make
  # the script actually read it.
  staticMac = if nbdStaticIface != null then nbdStaticIface.mac else protocol.targetMac;
  staticIp = if nbdStaticIface != null then nbdStaticIface.ip else protocol.targetIp;
  staticPfx = if nbdStaticIface != null then nbdStaticIface.prefix else protocol.prefix;
  shellLib = ''
    nanokvm_target_mac=${staticMac}
    nanokvm_target_ip=${staticIp}
    nanokvm_host_ip=${nbdHost}
    nanokvm_prefix=${staticPfx}
    nanokvm_port_status=${toString protocol.ports.statusSink}
    nanokvm_port_nbd_rootfs=${toString nbdPort}

    nanokvm_cmdline_value() {
      local key="$1" item
      for item in $(cat /proc/cmdline 2>/dev/null || true); do
        case "$item" in
          "$key="*)
            printf '%s\n' "''${item#"$key="}"
            return 0
            ;;
        esac
      done
      return 1
    }

    nanokvm_apply_nbd_cmdline() {
      local value
      if value="$(nanokvm_cmdline_value nanokvm.nbd_rootfs_host)"; then
        nanokvm_host_ip="$value"
      fi
      if value="$(nanokvm_cmdline_value nanokvm.nbd_rootfs_port)"; then
        nanokvm_port_nbd_rootfs="$value"
      fi
    }

    nanokvm_apply_nbd_cmdline

    nanokvm_find_iface() {
      local desired="''${1:-$nanokvm_target_mac}" path observed
      for path in /sys/class/net/*; do
        [ -r "$path/address" ] || continue
        observed="$(cat "$path/address" 2>/dev/null || true)"
        if [ "$observed" = "$desired" ]; then
          printf '%s\n' "''${path##*/}"
          return 0
        fi
      done
      for path in /sys/class/net/*; do
        [ -r "$path/type" ] || continue
        [ "$(cat "$path/type" 2>/dev/null || true)" = 1 ] || continue
        printf '%s\n' "''${path##*/}"
        return 0
      done
      return 1
    }

    nanokvm_wait_iface() {
      local timeout="''${1:-30}" iface attempts=$(( ''${1:-30} * 10 ))
      for _ in $(seq 1 "$attempts"); do
        iface="$(nanokvm_find_iface 2>/dev/null || true)"
        if [ -n "$iface" ]; then
          printf '%s\n' "$iface"
          return 0
        fi
        sleep 0.1
      done
      return 1
    }
  '';

  mkTargetScript = name: body:
    pkgs.writeShellScript name ''
      set -eu
      export PATH=${lib.makeBinPath targetTools}
      ${shellLib}

      ${body}
    '';

  runRootNbd = mkTargetScript "nanokvm-run-root-nbd" ''
    pid_file=/run/nanokvm-root-nbd.pid
    udevadm=${systemdPackage}/bin/udevadm

    read_live_nbd_pid() {
      [ -r /sys/block/nbd0/pid ] || return 1
      pid="$(cat /sys/block/nbd0/pid 2>/dev/null || true)"
      case "$pid" in
        "" | 0) return 1 ;;
      esac
      kill -0 "$pid" 2>/dev/null || return 1
      printf '%s\n' "$pid"
    }

    # NBD attach only emits a "change" uevent (the "add" fires when the
    # nbd kmod registers the disk at capacity 0). Until systemd-udevd
    # reprobes on that change, /dev/nbd0's SYSTEMD_READY tag stays 0
    # and dev-nbd0.device never becomes active — which blocks the
    # sysroot mount unit indefinitely. So trigger+settle by hand once
    # the client is up.
    publish_nbd_device() {
      [ -x "$udevadm" ] || return 0
      "$udevadm" trigger --action=change ${nbdDevice} 2>/dev/null || true
      "$udevadm" settle --timeout=5 2>/dev/null || true
    }

    if [ -e /dev/ttyGS0 ]; then
      exec > >(tee /dev/ttyGS0) 2>&1
    fi

    echo "nbd-root: starting root NBD setup"

    ${
      if nbdStaticIface == null
      then ''
        # Wait for routing to the NBD host to appear (DHCP/networkd brings
        # up wlan0 etc.). Skip the static-iface bring-up.
        for _ in $(seq 1 120); do
          if ip route get "$nanokvm_host_ip" >/dev/null 2>&1; then
            echo "nbd-root: route to $nanokvm_host_ip ready"
            break
          fi
          sleep 0.5
        done
      ''
      else ''
        iface="$(nanokvm_wait_iface 20)" || {
          echo "nbd-root: USB gadget network did not appear" >&2
          exit 1
        }

        ip link set "$iface" up || true
        ip addr replace "$nanokvm_target_ip/$nanokvm_prefix" dev "$iface" || true
        ip addr show "$iface" || true
      ''
    }

    if [ -s "$pid_file" ]; then
      pid="$(cat "$pid_file")"
      if kill -0 "$pid" 2>/dev/null; then
        echo "nbd-root: keeping existing ${nbdDevice} client pid $pid"
        publish_nbd_device
        exit 0
      fi
      rm -f "$pid_file"
    fi

    if ${nbdClient} -c ${nbdDevice} >/dev/null 2>&1; then
      if live_pid="$(read_live_nbd_pid)"; then
        echo "$live_pid" > "$pid_file"
        echo "nbd-root: adopted existing ${nbdDevice} client pid $live_pid"
      fi
      echo "nbd-root: ${nbdDevice} is already connected"
      publish_nbd_device
      exit 0
    fi

    echo "nbd-root: connecting ${nbdDevice} to $nanokvm_host_ip:$nanokvm_port_nbd_rootfs"
    # systemd's `broadcast_signal()` in src/shared/killall.c does
    # `kill(-1, SIGSTOP)` → `killall(SIGTERM)` → `kill(-1, SIGCONT)`.
    # The trap-and-exec wrapper handles the SIGTERM half; the SIGSTOP
    # half used to be lethal because it interrupted
    # wait_event_interruptible inside nbd_start_device_ioctl with
    # -ERESTARTSYS and the kernel unconditionally tore down the
    # socket. The 0009 kernel patch (wait_event_killable) keeps the
    # wait alive across SIGSTOP/SIGCONT so /dev/nbd0 stays connected
    # through the switch-root transition. `-p` (persist) is NOT
    # used: with the kernel patch we don't need kernel-side
    # reconnect, and `-p` interacts badly with NBD_DO_IT cleanup
    # on this kernel (Device or resource busy storm).
    ( trap "" TERM HUP; exec ${nbdClient} -n --systemd-mark -N rootfs "$nanokvm_host_ip" "$nanokvm_port_nbd_rootfs" ${nbdDevice} ) &
    client=$!
    echo "$client" > "$pid_file"

    for try in $(seq 1 300); do
      if ${nbdClient} -c ${nbdDevice} >/dev/null 2>&1; then
        echo "nbd-root: ${nbdDevice} connected"
        publish_nbd_device
        exit 0
      fi
      if ! kill -0 "$client" 2>/dev/null; then
        wait "$client" 2>/dev/null || true
        rm -f "$pid_file"
        echo "nbd-root: NBD client exited before ${nbdDevice} connected" >&2
        exit 1
      fi
      if [ "$try" = 1 ] || [ "$try" = 300 ]; then
        echo "nbd-root: waiting for ${nbdDevice} ($try/300)" >&2
      fi
      sleep 0.1
    done

    echo "nbd-root: unable to connect ${nbdDevice} to $nanokvm_host_ip:$nanokvm_port_nbd_rootfs" >&2
    kill "$client" 2>/dev/null || true
    wait "$client" 2>/dev/null || true
    rm -f "$pid_file"
    exit 1
  '';

  pushDebugStatus = pkgs.writeShellScript "nanokvm-push-debug-status" ''
    set -u

    if [ "''${NANOKVM_DEBUG_STATUS_MARKED:-0}" != 1 ]; then
      export NANOKVM_DEBUG_STATUS_MARKED=1
      exec -a @nanokvm-debug-status ${pkgs.bash}/bin/bash "$0" "$@"
    fi

    cat=${pkgs.busybox}/bin/cat
    date=${pkgs.busybox}/bin/date
    ls=${pkgs.busybox}/bin/ls
    ps=${pkgs.busybox}/bin/ps
    sleep=${pkgs.busybox}/bin/sleep
    systemctl=${systemdPackage}/bin/systemctl
    tr=${pkgs.busybox}/bin/tr
    stage="''${1:-unknown}"

    # systemd's MANAGER_SWITCH_ROOT broadcasts SIGTERM to everything,
    # but if this process is stuck in an uninterruptible NBD read at the
    # time of the broadcast (the new /nix/store overlay is backed by
    # nbd0), the signal can't be delivered, the bash survives into
    # stage 2 stale, and shadows the real stage-2 pusher. A SIGTERM
    # trap that calls `exit 0` gives the kernel a delivery point as
    # soon as the syscall returns.
    trap 'exit 0' TERM HUP

    while true; do
      {
        echo "===== nanokvm debug status ====="
        echo "stage: $stage"
        echo "time: $("$date" 2>/dev/null || true)"
        echo
        echo "--- cmdline"
        "$cat" /proc/cmdline 2>/dev/null || true
        echo
        echo "--- nbd"
        "$ls" -l /dev/nbd0 /sys/block/nbd0/pid 2>/dev/null || true
        "$cat" /sys/block/nbd0/pid 2>/dev/null || true
        echo
        echo "--- jobs"
        "$systemctl" list-jobs --no-pager 2>&1 || true
        echo
        echo "--- failed"
        SYSTEMD_COLORS=0 "$systemctl" --failed --no-pager 2>&1 || true
        echo
        echo "--- nanokvm-root-nbd"
        SYSTEMD_COLORS=0 "$systemctl" status nanokvm-root-nbd.service --no-pager -l 2>&1 || true
        echo
        echo "--- initrd-nixos-activation"
        SYSTEMD_COLORS=0 "$systemctl" status initrd-nixos-activation.service --no-pager -l 2>&1 || true
        activation_pid="$("$systemctl" show -P MainPID initrd-nixos-activation.service 2>/dev/null || true)"
        if [ -n "$activation_pid" ] && [ "$activation_pid" != 0 ]; then
          echo "activation MainPID: $activation_pid"
          echo "activation cmdline:"
          "$tr" '\0' ' ' <"/proc/$activation_pid/cmdline" 2>/dev/null || true
          echo
          echo "activation wchan:"
          "$cat" "/proc/$activation_pid/wchan" 2>/dev/null || true
          echo
          echo "activation stack:"
          "$cat" "/proc/$activation_pid/stack" 2>/dev/null || true
          echo
          echo "activation children:"
          "$cat" /proc/"$activation_pid"/task/*/children 2>/dev/null || true
          echo
        fi
        echo "--- stage2 services"
        SYSTEMD_COLORS=0 "$systemctl" status sshd.service nanokvm-server.service multi-user.target --no-pager -l 2>&1 || true
        echo
        echo "--- processes"
        "$ps" 2>&1 || true
        echo
        echo "--- mounts"
        "$cat" /proc/mounts 2>/dev/null || true
        echo "===== end status ====="
      } >/dev/tcp/${protocol.hostIp}/${toString protocol.ports.statusSink} 2>/dev/null || true

      "$sleep" 5
    done
  '';

  rootNbdServiceConfig = {
    Type = "forking";
    PIDFile = "/run/nanokvm-root-nbd.pid";
    ExecStart = runRootNbd;
    KillMode = "none";
    Restart = "always";
    RestartSec = "500ms";
    SendSIGKILL = false;
    TimeoutStartSec = "infinity";
    # initrd-cleanup isolates initrd-switch-root.target before handing
    # off to stage 2; in stage 2, normal target transitions and shutdown
    # must not pull the live store out from under systemd. Override
    # ExecStop in both layers.
    ExecStop = lib.mkForce [ "" ];
  };
in
{
  imports = [ ./usb-control.nix ];

  options.nanokvm.nbdLive = with lib; {
    host = mkOption {
      type = types.str;
      default = protocol.hostIp;
      description = ''
        IP address the target's nbd-client connects to for the rootfs.
        Defaults to the USB-ECM host address; override for wlan0-based
        diagnostics where the host serves NBD on its LAN address.
      '';
    };
    port = mkOption {
      type = types.port;
      default = protocol.ports.nbdRootfs;
      description = "TCP port for the rootfs NBD export.";
    };
    staticIface = mkOption {
      type = types.nullOr (types.submodule {
        options = {
          mac = mkOption {
            type = types.str;
            description = ''
              MAC address of the iface to find in /sys/class/net.
              Must match the configfs `host_addr` (see
              modules/sg2002-usb-gadget-initrd.nix).
            '';
          };
          ip = mkOption {
            type = types.str;
            description = "IPv4 address to assign to the iface (no prefix).";
          };
          prefix = mkOption {
            type = types.str;
            description = "Netmask prefix length, e.g. \"24\".";
          };
        };
      });
      default = {
        mac = protocol.targetMac;
        ip = protocol.targetIp;
        prefix = protocol.prefix;
      };
      description = ''
        Static-IP iface to bring up at NBD-mount time, identified by
        MAC. Set to null when networkd / wpa_supplicant brings up
        the routing instead (wifi mode).

        All three fields are read by `runRootNbd` and threaded into
        the shell prelude (see `staticMac`/`staticIp`/`staticPfx`
        bindings above). Previous versions ignored them; T3.
      '';
    };
  };

  config = {
    nanokvm.usbControl = {
      initrd.enable = true;
      stage2.enable = true;
    };

    fileSystems = lib.mkForce {
      "/" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=0755" ];
      };
      "/nix/.ro-store" = {
        device = nbdDevice;
        fsType = "erofs";
        options = [ "ro" ];
        neededForBoot = true;
      };
      "/nix/.rw-store" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=0755" ];
        neededForBoot = true;
      };
      "/nix/store" = {
        overlay = {
          lowerdir = [ "/nix/.ro-store" ];
          upperdir = "/nix/.rw-store/store";
          workdir = "/nix/.rw-store/work";
        };
        neededForBoot = true;
      };
      "/tmp" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=1777" ];
      };
    };

    sg2002.initrd.pruneKernelModules = true;
    sg2002.initrd.availableKernelModules = [
      "af_packet"
      "erofs"
      "loop"
      "overlay"
    ];

    boot.initrd.network.flushBeforeStage2 = lib.mkForce false;

    boot.initrd.systemd = {
      services.usb-gadget = {
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

      # Diagnostic: initrd-cleanup.service normally runs
      # `systemctl --no-block isolate initrd-switch-root.target`,
      # which stops all units that aren't in that target. Even though
      # nanokvm-root-nbd has `IgnoreOnIsolate = true`, the mount units
      # (sysroot-nix-.ro\x2dstore.mount, sysroot-nix-store.mount) get
      # stopped — which umounts /dev/nbd0 → nbd-client's last opener
      # closes → if `NBD_RT_DISCONNECT_ON_CLOSE` is set, the kernel
      # tears the device down → all subsequent reads from
      # /sysroot/nix/store EIO and stage 2 never reaches its init.
      # ACM kernel log (2026-05-11 18:18) shows `block nbd0: shutting
      # down sockets` at uptime 58.329 s, 46 ms BEFORE
      # `systemd-journald received SIGTERM from PID 1` — confirming
      # the disconnect happens during the isolate sweep, not the
      # broadcast.
      #
      # Replace `isolate` with a plain `start` so nothing gets
      # stopped, then activate initrd-switch-root.service manually.
      services.initrd-cleanup = {
        overrideStrategy = "asDropinIfExists";
        serviceConfig.ExecStart = lib.mkForce [
          ""
          "${systemdPackage}/bin/systemctl --no-block start initrd-switch-root.target"
        ];
      };

      # initrd-udevadm-cleanup-db.service has `Conflicts=systemd-udevd.service`.
      # When it activates (just before initrd-switch-root.target), systemd
      # forcibly stops systemd-udevd — which closes systemd-udevd's open fd
      # on /dev/nbd0 (held from probing). If the NBD negotiation set
      # NBD_FLAG_DISCONNECT_ON_CLOSE, the kernel tears the device down on
      # last-close, even with nbd-client's own fd still alive. Override
      # to a no-op so systemd-udevd is left running past the switch-root.
      services.initrd-udevadm-cleanup-db = {
        overrideStrategy = "asDropinIfExists";
        unitConfig.Conflicts = lib.mkForce [ ];
        serviceConfig.ExecStart = lib.mkForce [
          ""
          "${pkgs.coreutils}/bin/true"
        ];
      };

      services.nanokvm-root-nbd = {
        description = "Connect the NanoKVM live root NBD device";
        wantedBy = [ "initrd-root-fs.target" ];
        wants = [
          "systemd-networkd.service"
          "usb-gadget.service"
        ];
        after = [
          "systemd-networkd.service"
          "usb-gadget.service"
        ];
        before = [
          rootFsTarget
          "initrd-root-fs.target"
        ];
        unitConfig = {
          DefaultDependencies = false;
          IgnoreOnIsolate = true;
          StartLimitBurst = 0;
          StartLimitIntervalSec = 0;
          SurviveFinalKillSignal = true;
        };
        serviceConfig = rootNbdServiceConfig;
      };

      services."usb-debug-status" = {
        description = "Push initrd status over the USB debug network";
        wantedBy = [ "initrd-root-fs.target" ];
        after = [
          "systemd-networkd.service"
          "usb-gadget.service"
        ];
        wants = [
          "systemd-networkd.service"
          "usb-gadget.service"
        ];
        before = [ "initrd-root-fs.target" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          ExecStart = "${pushDebugStatus} initrd";
          Restart = "always";
          RestartSec = "1s";
        };
      };

      storePaths = [
        runRootNbd
        pushDebugStatus
        # runRootNbd must never fall through to BusyBox's incompatible
        # nbd-client applet when the optional kexec control plane is off.
        pkgs.nbd-client-minimal
      ];
    };

    systemd.services.nanokvm-root-nbd = {
      description = "Keep the NanoKVM live root NBD device connected";
      wantedBy = [ "multi-user.target" ];
      unitConfig = {
        DefaultDependencies = false;
        IgnoreOnIsolate = true;
        StartLimitBurst = 0;
        StartLimitIntervalSec = 0;
        SurviveFinalKillSignal = true;
      };
      serviceConfig = rootNbdServiceConfig;
    };

    systemd.services.usb-gadget = {
      description = "Preserve the initrd USB gadget across switch-root";
      unitConfig = {
        DefaultDependencies = false;
        IgnoreOnIsolate = true;
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

    systemd.services.usb-debug-status = {
      description = "Push stage2 status over the USB debug network";
      wantedBy = [ "sysinit.target" ];
      after = [ "systemd-networkd.service" ];
      wants = [ "systemd-networkd.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        ExecStart = "${pushDebugStatus} stage2";
        Restart = "always";
        RestartSec = "1s";
      };
    };
  };
}
