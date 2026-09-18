#!/usr/bin/env bash
set -euo pipefail

self="${BASH_SOURCE[0]}"
case "$self" in
  /*) ;;
  *) self="$PWD/$self" ;;
esac
capture_runner_pid=

usage() {
  cat <<'EOF'
Usage: capture-usb-oled-top [usb-oled-top options]

Records `usb-oled-top` output to an asciicast and renders an animated GIF.

Environment:
  NANOKVM_CAPTURE_DIR=media/captures
  NANOKVM_CAPTURE_NAME=usb-oled-top-YYYYmmdd-HHMMSS
  NANOKVM_CAPTURE_SIZE=100x28
  NANOKVM_CAPTURE_TIMEOUT=300
  NANOKVM_CAPTURE_POST_ROLL=3
  NANOKVM_CAPTURE_IDLE_LIMIT=1.5
  NANOKVM_CAPTURE_THEME=asciinema
  NANOKVM_CAPTURE_FONT_DIR=
  NANOKVM_CAPTURE_FONT_FAMILY=DejaVu Sans Mono
  NANOKVM_CAPTURE_WAIT_SSH=1
  NANOKVM_CAPTURE_SSH_TIMEOUT=600
  NANOKVM_CAPTURE_SSH_HOST=10.55.0.1
  NANOKVM_CAPTURE_SSH_USER=root
  NANOKVM_CAPTURE_SSH_PASSWORD=nixos
  NANOKVM_CAPTURE_KEEP_RUNNER=1
  NANOKVM_ATTACH=none

By default the USB/NBD runner is left alive after the GIF is written.
Set NANOKVM_CAPTURE_KEEP_RUNNER=0 to stop it when capture exits.
EOF
}

ssh_target() {
  local host="$1"
  local user="$2"
  local password="$3"
  local command="$4"

  SSHPASS="$password" sshpass -e ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 \
    -o LogLevel=ERROR \
    "$user@$host" \
    "$command"
}

wait_for_target_ssh() {
  local host="$1"
  local user="$2"
  local password="$3"
  local timeout="$4"
  local deadline=$((SECONDS + timeout))

  while [ "$SECONDS" -lt "$deadline" ]; do
    if timeout 1 bash -c ":</dev/tcp/$host/22" 2>/dev/null \
        && ssh_target "$host" "$user" "$password" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 1
}

run_target_report() {
  local host="${NANOKVM_CAPTURE_SSH_HOST:-10.55.0.1}"
  local user="${NANOKVM_CAPTURE_SSH_USER:-root}"
  local password="${NANOKVM_CAPTURE_SSH_PASSWORD:-nixos}"
  local timeout="${NANOKVM_CAPTURE_SSH_TIMEOUT:-600}"

  if [ "${NANOKVM_CAPTURE_WAIT_SSH:-1}" = 0 ]; then
    return 0
  fi

  if ! command -v ssh >/dev/null 2>&1 || ! command -v sshpass >/dev/null 2>&1; then
    echo
    echo "[capture] ssh/sshpass not available; skipping target report"
    return 0
  fi

  echo
  echo "[capture] waiting for SSH on $user@$host..."
  if ! wait_for_target_ssh "$host" "$user" "$password" "$timeout"; then
    echo "[capture] SSH did not answer after ${timeout}s"
    return 1
  fi

  echo "[capture] SSH is ready"
  echo
  echo "$ ssh $user@$host 'uname -a; free -m; cat /proc/cpuinfo; cat /etc/os-release; df -h / /nix/.ro-store'"
  if ! ssh_target "$host" "$user" "$password" '
    set -eu
    echo "== uname -a =="
    uname -a
    echo
    echo "== free -m =="
    free -m
    echo
    echo "== /proc/cpuinfo =="
    cat /proc/cpuinfo
    echo
    echo "== /etc/os-release =="
    cat /etc/os-release
    echo
    echo "== df -h =="
    df -h / /nix/.ro-store 2>/dev/null || df -h
  '; then
    echo "[capture] target report command failed"
    return 1
  fi
}

tail_log() {
  local log="$1"
  local pidfile="$2"
  local statusfile="$3"
  local timeout="${NANOKVM_CAPTURE_TIMEOUT:-300}"
  local post_roll="${NANOKVM_CAPTURE_POST_ROLL:-3}"
  local next_line=1
  local deadline=$((SECONDS + timeout))
  local done=0
  local failed=0
  local report=0

  finish_tail() {
    local status="$1"
    printf '%s\n' "$status" > "$statusfile"
    [ "$status" = ok ]
  }

  emit_new_lines() {
    local total line
    if [ ! -f "$log" ]; then
      return 0
    fi

    total="$(wc -l < "$log" | tr -d ' ')"
    if [ "$total" -lt "$next_line" ]; then
      return 0
    fi

    while IFS= read -r line; do
      printf '%s\n' "$line"
      case "$line" in
        *"SSH is up:"* | \
        *"NanoKVM web app target:"* | \
        *"SSH did not answer yet; keeping NBD server running for inspection"* | \
        *"leave this process running; Ctrl-C stops the NBD backing store"* | \
        *"not attaching to target shell; rootfs NBD is running"* | \
        *"shell detached; rootfs NBD is still running"*)
          done=1
          report=1
          ;;
        *"failed to start target kexec agent"* | \
        *"unable to start rootfs nbd-server"* | \
        *"nbd-server exited early"*)
          done=1
          failed=1
          ;;
      esac
    done < <(sed -n "${next_line},${total}p" "$log")

    next_line=$((total + 1))
  }

  while [ "$SECONDS" -lt "$deadline" ]; do
    emit_new_lines

    if [ "$done" = 1 ]; then
      sleep "$post_roll"
      emit_new_lines
      if [ "$report" = 1 ]; then
        run_target_report || failed=1
      fi
      if [ "$failed" = 0 ]; then
        finish_tail ok
      else
        finish_tail failed
      fi
      return $?
    fi

    if [ -s "$pidfile" ]; then
      local pid
      pid="$(cat "$pidfile" 2>/dev/null || true)"
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
        emit_new_lines
        if [ "$failed" = 0 ]; then
          finish_tail ok
        else
          finish_tail failed
        fi
        return $?
      fi
    fi

    sleep 0.25
  done

  emit_new_lines
  printf '[capture] timed out after %ss\n' "$timeout"
  if run_target_report; then
    finish_tail ok
  else
    finish_tail failed
  fi
}

ensure_capture_tools() {
  if command -v asciinema >/dev/null 2>&1 && command -v agg >/dev/null 2>&1; then
    return 0
  fi

  if command -v nix >/dev/null 2>&1; then
    exec nix shell nixpkgs#asciinema nixpkgs#asciinema-agg -c "$self" "$@"
  fi

  echo "capture-usb-oled-top: asciinema and agg are required" >&2
  exit 127
}

repo_root() {
  if [ -n "${NANOKVM_REPO_ROOT:-}" ]; then
    printf '%s\n' "$NANOKVM_REPO_ROOT"
    return 0
  fi

  git rev-parse --show-toplevel 2>/dev/null || pwd
}

print_runner_command() {
  if [ -n "${NANOKVM_USB_OLED_TOP:-}" ]; then
    printf '$ %q' "$NANOKVM_USB_OLED_TOP"
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
  else
    printf '$ nix run .#usb-oled-top --'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
  fi
}

run_usb_oled_top() {
  if [ -n "${NANOKVM_USB_OLED_TOP:-}" ]; then
    exec "$NANOKVM_USB_OLED_TOP" "$@"
  fi

  exec nix run .#usb-oled-top -- "$@"
}

record_asciicast() {
  local size="$1"
  local cols="$2"
  local rows="$3"
  local idle="$4"
  local command="$5"
  local cast="$6"

  if asciinema rec --help >/dev/null 2>&1; then
    asciinema rec \
      --overwrite \
      --cols "$cols" \
      --rows "$rows" \
      --idle-time-limit "$idle" \
      --quiet \
      --command "$command" \
      "$cast"
  else
    asciinema record \
      --overwrite \
      --headless \
      --window-size "$size" \
      --idle-time-limit "$idle" \
      --command "$command" \
      "$cast"
  fi
}

main() {
  case "${1:-}" in
    --tail-log)
      if [ "$#" -ne 4 ]; then
        echo "capture-usb-oled-top: --tail-log requires LOG PIDFILE and STATUSFILE" >&2
        exit 2
      fi
      tail_log "$2" "$3" "$4"
      exit 0
      ;;
    -h | --help)
      usage
      exit 0
      ;;
  esac

  ensure_capture_tools "$@"

  cd "$(repo_root)"

  local out_dir name size cols rows idle theme font_dir font_family cast gif log pidfile statusfile
  out_dir="${NANOKVM_CAPTURE_DIR:-media/captures}"
  name="${NANOKVM_CAPTURE_NAME:-usb-oled-top-$(date +%Y%m%d-%H%M%S)}"
  size="${NANOKVM_CAPTURE_SIZE:-100x28}"
  cols="${size%x*}"
  rows="${size#*x}"
  idle="${NANOKVM_CAPTURE_IDLE_LIMIT:-1.5}"
  theme="${NANOKVM_CAPTURE_THEME:-asciinema}"
  font_dir="${NANOKVM_CAPTURE_FONT_DIR:-}"
  font_family="${NANOKVM_CAPTURE_FONT_FAMILY:-DejaVu Sans Mono}"

  if [ "$cols" = "$size" ] || [ -z "$cols" ] || [ -z "$rows" ]; then
    echo "capture-usb-oled-top: NANOKVM_CAPTURE_SIZE must look like 100x28" >&2
    exit 2
  fi

  mkdir -p "$out_dir"
  cast="$out_dir/$name.cast"
  gif="$out_dir/$name.gif"
  log="$out_dir/$name.log"
  pidfile="$out_dir/$name.pid"
  statusfile="$out_dir/$name.status"
  : > "$log"
  : > "$pidfile"
  : > "$statusfile"

  local keep_runner
  keep_runner="${NANOKVM_CAPTURE_KEEP_RUNNER:-1}"

  (
    export NANOKVM_ATTACH="${NANOKVM_ATTACH:-none}"
    export NANOKVM_STATUS_LISTEN="${NANOKVM_STATUS_LISTEN:-0}"
    print_runner_command "$@"
    run_usb_oled_top "$@"
  ) >"$log" 2>&1 &

  local runner_pid
  runner_pid="$!"
  capture_runner_pid="$runner_pid"
  printf '%s\n' "$runner_pid" > "$pidfile"

  if [ "$keep_runner" != 1 ]; then
    trap 'if [ -n "${capture_runner_pid:-}" ]; then kill "$capture_runner_pid" 2>/dev/null || true; fi' EXIT
  fi

  local tail_command
  tail_command="$(printf '%q ' "$self" --tail-log "$log" "$pidfile" "$statusfile")"

  echo "[capture] recording $cast"
  echo "[capture] source log $log"
  record_asciicast "$size" "$cols" "$rows" "$idle" "$tail_command" "$cast"

  local capture_status
  capture_status="$(cat "$statusfile" 2>/dev/null || true)"
  if [ "$capture_status" != ok ]; then
    echo "[capture] source failed; not rendering GIF"
    echo "[capture] wrote $cast"
    echo "[capture] source log $log"
    return 1
  fi

  echo "[capture] rendering $gif"
  local -a agg_args=(
    --cols "$cols"
    --rows "$rows"
    --idle-time-limit "$idle"
    --theme "$theme"
    --quiet
  )
  if [ -n "$font_dir" ]; then
    agg_args+=(--font-dir "$font_dir")
  fi
  if [ -n "$font_family" ]; then
    agg_args+=(--font-family "$font_family")
  fi
  agg "${agg_args[@]}" "$cast" "$gif"

  echo "[capture] wrote $cast"
  echo "[capture] wrote $gif"

  if [ "$keep_runner" = 1 ]; then
    if kill -0 "$runner_pid" 2>/dev/null; then
      echo "[capture] usb-oled-top is still running as pid $runner_pid"
      echo "[capture] stop it with: kill $runner_pid"
      disown "$runner_pid" 2>/dev/null || true
    else
      echo "[capture] usb-oled-top exited; see $log"
    fi
  else
    echo "[capture] stopping usb-oled-top pid $runner_pid"
    kill "$runner_pid" 2>/dev/null || true
    wait "$runner_pid" 2>/dev/null || true
    capture_runner_pid=
    trap - EXIT
  fi
}

main "$@"
