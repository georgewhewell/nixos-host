# Bash prelude included verbatim in every host-side runner produced by
# lib/runners.nix. Defines the protocol constants (from lib/protocol.nix)
# and the helper functions every runner shares — interface lookup,
# `sudo` wrapper, NBD-server orphan handling, kexec request sender, ACM
# device discovery for picocom.
#
# Pure: takes the protocol attrset and returns the string. No
# dependencies on flake context. Consumers do:
#
#     hostShellPrelude = import ./lib/host-prelude.nix protocol;
#
# and interpolate `${hostShellPrelude}` at the top of a runner script.
protocol:
let
  cv181xRomPresence = import ./cv181x-rom-presence.nix;
in
''
  export nanokvm_target_mac=${protocol.targetMac}
  export nanokvm_host_mac=${protocol.hostMac}
  export nanokvm_target_ip=${protocol.targetIp}
  export nanokvm_host_ip=${protocol.hostIp}
  export nanokvm_prefix=${protocol.prefix}
  export nanokvm_port_shell=${toString protocol.ports.debugShell}
  export nanokvm_port_status=${toString protocol.ports.statusSink}
  export nanokvm_port_kexec=${toString protocol.ports.kexecCtrl}
  export nanokvm_port_wifi_config=${toString protocol.ports.wifiConfig}
  export nanokvm_port_nbd_rootfs=${toString protocol.ports.nbdRootfs}
  export nanokvm_port_nbd_payload=${toString protocol.ports.nbdPayload}

  ${cv181xRomPresence}

  as_root() {
    if [ "$(id -u)" -eq 0 ]; then
      "$@"
    else
      sudo -n "$@"
    fi
  }

  find_usb_iface() {
    shopt -s nullglob
    local path mac
    for path in /sys/class/net/*; do
      [ -e "$path/address" ] || continue
      mac="$(cat "$path/address" 2>/dev/null || true)"
      if [ "$mac" = "$nanokvm_host_mac" ]; then
        basename "$path"
        return 0
      fi
    done
    return 1
  }

  wait_usb_iface() {
    local timeout="''${1:-40}" iface
    local attempts=$(( timeout * 4 ))
    for _ in $(seq 1 "$attempts"); do
      if [ -n "''${USB_IFACE:-}" ]; then
        if [ -d "/sys/class/net/$USB_IFACE" ]; then
          printf '%s\n' "$USB_IFACE"
          return 0
        fi
      else
        iface="$(find_usb_iface || true)"
        if [ -n "$iface" ]; then
          printf '%s\n' "$iface"
          return 0
        fi
      fi
      sleep 0.25
    done
    return 1
  }

  wait_tcp() {
    local host="$1" port="$2" timeout="''${3:-40}"
    local attempts=$(( timeout * 4 ))
    for _ in $(seq 1 "$attempts"); do
      if nc -z -w 1 "$host" "$port" >/dev/null 2>&1; then
        return 0
      fi
      sleep 0.25
    done
    return 1
  }

  wait_tcp_down() {
    local host="$1" port="$2" timeout="''${3:-40}"
    local attempts=$(( timeout * 4 ))
    for _ in $(seq 1 "$attempts"); do
      if ! nc -z -w 1 "$host" "$port" >/dev/null 2>&1; then
        return 0
      fi
      sleep 0.25
    done
    return 1
  }

  start_status_sink() {
    local label="''${1:-host}"
    if [ "''${NANOKVM_STATUS_LISTEN:-0}" != 1 ]; then
      echo "[$label] target status stream disabled; set NANOKVM_STATUS_LISTEN=1 for debug spam"
      return 0
    fi

    echo "[$label] listening for target status on $nanokvm_host_ip:$nanokvm_port_status"
    nc -lk -s "$nanokvm_host_ip" -p "$nanokvm_port_status" &
    status_pid=$!
  }

  attach_debug_shell() {
    local label="''${1:-host}" timeout="''${2:-180}"
    echo "[$label] waiting for target shell on $nanokvm_target_ip:$nanokvm_port_shell..."
    if ! wait_tcp "$nanokvm_target_ip" "$nanokvm_port_shell" "$timeout"; then
      echo "[$label] target shell did not answer on $nanokvm_target_ip:$nanokvm_port_shell" >&2
      return 1
    fi

    echo "[$label] attached to target shell. Exit the shell to detach; Ctrl-C stops this runner."
    if command -v telnet >/dev/null 2>&1; then
      telnet "$nanokvm_target_ip" "$nanokvm_port_shell"
    else
      nc "$nanokvm_target_ip" "$nanokvm_port_shell"
    fi
  }

  attach_debug_shell_after_reconnect() {
    local label="''${1:-host}" down_timeout="''${2:-45}" up_timeout="''${3:-180}"
    if wait_tcp "$nanokvm_target_ip" "$nanokvm_port_shell" 1; then
      echo "[$label] waiting for previous target shell to disappear..."
      wait_tcp_down "$nanokvm_target_ip" "$nanokvm_port_shell" "$down_timeout" || true
    fi
    attach_debug_shell "$label" "$up_timeout"
  }

  find_tcp_listeners() {
    local port="$1"
    ss -tlnp -H "sport = :$port" 2>/dev/null \
      | grep -oP 'pid=\K[0-9]+' \
      | sort -u \
      || true
  }

  tcp_port_busy() {
    local port="$1"
    ss -Htan "sport = :$port" 2>/dev/null | grep -q .
  }

  free_tcp_listener() {
    local label="$1" port="$2" existing
    existing="$(find_tcp_listeners "$port")"
    if [ -z "''${existing:-}" ]; then
      return 0
    fi

    echo "[$label] killing orphan listener on :$port (pids: $existing)"
    # shellcheck disable=SC2086
    kill $existing 2>/dev/null || true
    for _ in $(seq 1 20); do
      sleep 0.1
      existing="$(find_tcp_listeners "$port")"
      [ -z "''${existing:-}" ] && return 0
    done

    if [ -n "''${existing:-}" ]; then
      echo "[$label] force-killing stubborn listener on :$port (pids: $existing)"
      # shellcheck disable=SC2086
      kill -KILL $existing 2>/dev/null || true
      sleep 0.2
    fi

    existing="$(find_tcp_listeners "$port")"
    if [ -n "''${existing:-}" ]; then
      echo "[$label] unable to free :$port (pids: $existing)" >&2
      return 1
    fi
  }

  process_tree_pids() {
    local pid="$1" child
    [ -d "/proc/$pid" ] || return 0
    printf '%s\n' "$pid"
    if [ -r "/proc/$pid/task/$pid/children" ]; then
      for child in $(cat "/proc/$pid/task/$pid/children" 2>/dev/null || true); do
        process_tree_pids "$child"
      done
    fi
  }

  kill_process_tree() {
    local root="$1" pids alive pid
    [ -n "''${root:-}" ] || return 0
    pids="$(process_tree_pids "$root" | sort -u)"
    [ -n "''${pids:-}" ] || return 0

    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
    for _ in $(seq 1 20); do
      alive=
      for pid in $pids; do
        if kill -0 "$pid" 2>/dev/null; then
          alive="$alive $pid"
        fi
      done
      [ -z "''${alive:-}" ] && break
      sleep 0.1
    done

    if [ -n "''${alive:-}" ]; then
      # shellcheck disable=SC2086
      kill -KILL $alive 2>/dev/null || true
    fi
    wait "$root" 2>/dev/null || true
  }

  find_nanokvm_rootfs_nbd_pids() {
    local cmdline pid cmd
    shopt -s nullglob
    for cmdline in /proc/[0-9]*/cmdline; do
      pid="''${cmdline%/cmdline}"
      pid="''${pid##*/}"
      [ "$pid" != "$$" ] || continue
      cmd="$({ tr '\0' ' ' < "$cmdline"; } 2>/dev/null || true)"
      case "$cmd" in
        *nbd-server*nanokvm-erofs-rootfs*)
          printf '%s\n' "$pid"
          ;;
      esac
    done | sort -u
  }

  cleanup_nanokvm_rootfs_nbd() {
    local label="''${1:-host}" pids pid
    if [ "''${NANOKVM_NBD_CLEANUP:-1}" = 0 ]; then
      return 0
    fi

    pids="$(find_nanokvm_rootfs_nbd_pids | tr '\n' ' ')"
    [ -n "''${pids// /}" ] || return 0

    echo "[$label] cleaning stale NanoKVM rootfs nbd-server pids: $pids"
    for pid in $pids; do
      kill_process_tree "$pid"
    done
  }

  choose_tcp_port() {
    local requested="''${1:-auto}" port
    case "$requested" in
      ""|auto|0)
        for _ in $(seq 1 100); do
          # Stay below Linux's usual ephemeral range. The previous
          # 20000-60999 range overlapped outbound client ports, and
          # nbd-server can fail bind(2) on TIME_WAIT sockets that do
          # not show up as TCP listeners.
          port="$(shuf -i 12000-19999 -n 1)"
          if ! tcp_port_busy "$port"; then
            printf '%s\n' "$port"
            return 0
          fi
        done
        echo "unable to find a free TCP port" >&2
        return 1
        ;;
      *[!0-9]*)
        echo "invalid TCP port: $requested" >&2
        return 1
        ;;
      *)
        if [ "$requested" -lt 1 ] || [ "$requested" -gt 65535 ]; then
          echo "invalid TCP port: $requested" >&2
          return 1
        fi
        printf '%s\n' "$requested"
        ;;
    esac
  }

  nbd_endpoint() {
    local bind_addr="$1" port="$2"
    if [ -n "$bind_addr" ]; then
      printf '%s:%s\n' "$bind_addr" "$port"
    else
      printf '%s\n' "$port"
    fi
  }

  write_nbd_config() {
    local label="$1" bind_addr="$2" port="$3" export_name="$4" export_path="$5" cfg
    cfg="$(mktemp -t "nanokvm-$label-nbd-XXXXXX.conf")"
    {
      printf '%s\n' '[generic]'
      if [ -n "$bind_addr" ]; then
        printf '  listenaddr = %s\n' "$bind_addr"
      fi
      printf '  port = %s\n' "$port"
      printf '\n'
      printf '[%s]\n' "$export_name"
      printf '  exportname = %s\n' "$export_path"
      printf '%s\n' '  readonly = true'
    } > "$cfg"
    printf '%s\n' "$cfg"
  }

  configure_host_iface() {
    local label="''${1:-host}" iface
    iface="$(wait_usb_iface 40)" || {
      echo "[$label] timed out waiting for USB ECM interface; set USB_IFACE=name to override detection" >&2
      return 1
    }
    if ! as_root true 2>/dev/null; then
      echo "[$label] passwordless sudo/root is required to configure $iface" >&2
      return 1
    fi

    # Some dev hosts have broad systemd-networkd rules such as
    # `Driver=cdc_ether` → `Bridge=...`; that immediately steals this
    # point-to-point gadget link back after `ip link set nomaster`.
    # Add a runtime-only, MAC-specific rule first so networkd leaves
    # NanoKVM on its private 10.55.0.0/24 link.
    if command -v networkctl >/dev/null 2>&1 \
        && networkctl status "$iface" >/dev/null 2>&1; then
      {
        printf '%s\n' '[Match]'
        printf 'MACAddress=%s\n' "$nanokvm_host_mac"
        printf '\n'
        printf '%s\n' '[Link]'
        printf '%s\n' 'RequiredForOnline=no'
        printf '\n'
        printf '%s\n' '[Network]'
        printf 'Address=%s/%s\n' "$nanokvm_host_ip" "$nanokvm_prefix"
        printf '%s\n' 'LinkLocalAddressing=no'
        printf '%s\n' 'ConfigureWithoutCarrier=yes'
      } | as_root networkctl edit --runtime --stdin "00-nanokvm-$iface.network" >/dev/null 2>&1 || true
      as_root networkctl reload >/dev/null 2>&1 || true
      as_root networkctl reconfigure "$iface" >/dev/null 2>&1 || true
    fi

    as_root ip link set "$iface" nomaster 2>/dev/null || true
    as_root ip addr replace "$nanokvm_host_ip/$nanokvm_prefix" dev "$iface"
    as_root ip link set "$iface" up
    echo "[$label] configured $iface as $nanokvm_host_ip/$nanokvm_prefix"
    printf '%s\n' "$iface"
  }

  list_acm() {
    shopt -s nullglob
    local d
    for d in /dev/ttyACM*; do
      [ -c "$d" ] && printf '%s\n' "$d"
    done
  }

  wait_acm() {
    local before="$1"
    local after new
    for _ in $(seq 1 160); do
      after="$(list_acm | sort)"
      new="$(
        comm -13 \
          <(printf '%s\n' "$before") \
          <(printf '%s\n' "$after") \
          | head -n1
      )"
      if [ -n "$new" ] && [ -c "$new" ]; then
        printf '%s\n' "$new"
        return 0
      fi
      new="$(printf '%s\n' "$after" | head -n1)"
      if [ -n "$new" ] && [ -c "$new" ]; then
        printf '%s\n' "$new"
        return 0
      fi
      sleep 0.25
    done
    return 1
  }

  kexec_send_request() {
    # Retry only if the connection itself failed. Once we get any
    # response, it's authoritative — `^OK ` means the agent
    # accepted the request, anything else is a real error.
    local request="$1" response rc last_rc=
    local attempts="''${2:-120}"
    for _ in $(seq 1 "$attempts"); do
      set +e
      response="$(printf '%s\n' "$request" | nc -N -w 5 "$nanokvm_target_ip" "$nanokvm_port_kexec" 2>&1)"
      rc=$?
      set -e
      if [ -n "$response" ]; then
        printf '%s\n' "$response"
        printf '%s\n' "$response" | grep -q '^OK '
        return $?
      fi
      if [ "$rc" -ne 0 ]; then
        last_rc="$rc"
      fi
      sleep 0.25
    done
    if [ -n "$last_rc" ]; then
      echo "no response from kexec control on $nanokvm_target_ip:$nanokvm_port_kexec after $attempts attempts (last nc exit $last_rc)" >&2
    else
      echo "no response from kexec control on $nanokvm_target_ip:$nanokvm_port_kexec after $attempts attempts" >&2
    fi
    return 1
  }
''
