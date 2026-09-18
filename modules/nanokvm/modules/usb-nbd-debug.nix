{ pkgs
, ...
}:
let
  protocol = import ../lib/protocol.nix;
  debugNbd = pkgs.writeShellScript "nanokvm-debug-nbd" ''
    set -eu

    bb=${pkgs.busybox}/bin/busybox
    nbd_client=${pkgs.nbd-client-minimal}/bin/nbd-client
    pid_file=/run/nanokvm-debug-nbd.pid
    usb_dev_mac=${protocol.targetMac}
    target_cidr=${protocol.targetIp}/${protocol.prefix}
    host_ip=${protocol.hostIp}
    status_port=${toString protocol.ports.statusSink}
    nbd_port=${toString protocol.ports.nbdRootfs}

    cmdline_value() {
      local key="$1" item
      for item in $("$bb" cat /proc/cmdline 2>/dev/null || true); do
        case "$item" in
          "$key="*)
            printf '%s\n' "''${item#"$key="}"
            return 0
            ;;
        esac
      done
      return 1
    }

    if value="$(cmdline_value nanokvm.nbd_rootfs_host)"; then
      host_ip="$value"
    fi
    if value="$(cmdline_value nanokvm.nbd_rootfs_port)"; then
      nbd_port="$value"
    fi

    find_usb_iface() {
      local path mac
      for path in /sys/class/net/*; do
        [ -r "$path/address" ] || continue
        mac="$("$bb" cat "$path/address" 2>/dev/null || true)"
        if [ "$mac" = "$usb_dev_mac" ]; then
          printf '%s\n' "''${path##*/}"
          return 0
        fi
      done
      for path in /sys/class/net/*; do
        [ -r "$path/type" ] || continue
        [ "$("$bb" cat "$path/type" 2>/dev/null || true)" = 1 ] || continue
        printf '%s\n' "''${path##*/}"
        return 0
      done
      return 1
    }

    if [ -e /dev/ttyGS0 ]; then
      exec > >("$bb" tee /dev/ttyGS0) 2>&1
    fi

    push_status() {
      {
        echo "===== nanokvm debug nbd ====="
        echo "$@"
        echo "--- ip"
        if usb_iface="$(find_usb_iface 2>/dev/null)"; then
          "$bb" ip addr show "$usb_iface" 2>&1 || true
        else
          "$bb" ip addr show 2>&1 || true
        fi
        echo "--- nbd"
        "$bb" ls -l /dev/nbd0 /sys/block/nbd0/pid 2>&1 || true
        "$bb" cat /sys/block/nbd0/pid 2>&1 || true
        echo "--- mounts"
        "$bb" cat /proc/mounts 2>&1 || true
        echo "===== end debug nbd ====="
      } >/dev/tcp/$host_ip/$status_port 2>/dev/null || true
    }

    echo "debug-nbd: configuring USB gadget network"
    for _ in $("$bb" seq 1 200); do
      if usb_iface="$(find_usb_iface 2>/dev/null)"; then
        break
      fi
      "$bb" sleep 0.1
    done

    if [ -z "''${usb_iface:-}" ]; then
      echo "debug-nbd: USB gadget network did not appear" >&2
      exit 1
    fi

    "$bb" ip link set "$usb_iface" up
    "$bb" ip addr replace "$target_cidr" dev "$usb_iface"
    "$bb" ip addr show "$usb_iface"

    echo "debug-nbd: checking host reachability"
    for _ in $("$bb" seq 1 120); do
      if "$bb" ping -c 1 -W 1 "$host_ip"; then
        break
      fi
      push_status "waiting for host"
      "$bb" sleep 0.5
    done

    if "$nbd_client" -c /dev/nbd0 >/dev/null 2>&1; then
      echo "debug-nbd: disconnecting stale /dev/nbd0 session"
      "$nbd_client" -d /dev/nbd0 || true
    fi

    echo "debug-nbd: connecting /dev/nbd0 to $host_ip:$nbd_port"
    "$nbd_client" -R -n -p --systemd-mark -N rootfs "$host_ip" "$nbd_port" /dev/nbd0 &
    client=$!
    echo "$client" > "$pid_file"

    for try in $("$bb" seq 1 300); do
      if "$nbd_client" -c /dev/nbd0 >/dev/null 2>&1; then
        echo "debug-nbd: /dev/nbd0 connected"
        break
      fi
      if ! kill -0 "$client" 2>/dev/null; then
        wait "$client" 2>/dev/null || true
        "$bb" rm -f "$pid_file"
        echo "debug-nbd: NBD client exited before connect" >&2
        push_status "nbd client exited before connect"
        exit 1
      fi
      if [ "$try" = 1 ] || [ "$try" = 300 ]; then
        push_status "waiting for nbd connect $try/300"
      fi
      "$bb" sleep 0.1
    done

    if ! "$nbd_client" -c /dev/nbd0 >/dev/null 2>&1; then
      echo "debug-nbd: unable to connect /dev/nbd0" >&2
      push_status "unable to connect nbd"
      exit 1
    fi

    echo "debug-nbd: mounting EROFS"
    "$bb" mkdir -p /mnt/nbd-root
    "$bb" mount -t erofs -o ro /dev/nbd0 /mnt/nbd-root
    "$bb" ls -la /mnt/nbd-root | "$bb" head
    echo "debug-nbd: mounted /dev/nbd0 at /mnt/nbd-root"
    push_status "mounted /dev/nbd0 at /mnt/nbd-root"

    wait "$client"
  '';
in
{
  config = {
    system.build.nanokvmDebugNbd = debugNbd;

    boot.initrd.systemd.services.nanokvm-debug-nbd = {
      description = "Automatically test NanoKVM NBD root mounting";
      wantedBy = [ "initrd.target" ];
      after = [ "usb-gadget.service" ];
      wants = [ "usb-gadget.service" ];
      serviceConfig = {
        ExecStart = debugNbd;
        Restart = "always";
        RestartSec = "2s";
      };
    };

    boot.initrd.systemd.storePaths = [
      debugNbd
      pkgs.nbd-client-minimal
    ];
  };
}
