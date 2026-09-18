usage() {
  cat >&2 <<'EOF'
Usage:
  nanokvm-host-keys recipient [options]
  nanokvm-host-keys inject-live [options]
  nanokvm-host-keys inject-sd [options]

Common options:
  --key-dir DIR        Host-key directory
                       default: $NANOKVM_HOST_KEY_DIR or $PWD
  --label LABEL        Log prefix label
                       default: $NANOKVM_HOST_KEY_LABEL or nanokvm-host-keys

Modes:
  recipient            Print age recipient derived from ssh_host_ed25519_key.pub.

  inject-live          Push keys through the initrd debug shell into the
                       mutable /etc overlay used by USB/NBD live images.
    --host HOST        Target debug-shell host/IP
    --port PORT        Target debug-shell TCP port
    --timeout SECONDS  Wait for debug shell, default 60

  inject-sd            Install keys into a mounted SD root via SSH to the
                       machine holding the card.
    --ssh-host HOST    SSH host, e.g. root@rock-5b
    --root-part DEV    Root partition on that host, e.g. /dev/mmcblk1p2
    --mount-point DIR  Remote mount point, default /tmp/nanokvm-sd-root

Environment:
  NANOKVM_HOST_KEY_GENERATE=0  inject-live exits without generating/pushing.
  NANOKVM_HOST_KEY_PERSIST=0   delete generated host-side keys after use.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

log() {
  echo "[$label] $*" >&2
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

key_dir="${NANOKVM_HOST_KEY_DIR:-$PWD}"
label="${NANOKVM_HOST_KEY_LABEL:-nanokvm-host-keys}"
mode="${1:-}"
[[ -n "$mode" ]] || {
  usage
  exit 2
}
shift

host=""
port=""
timeout=60
ssh_host=""
root_part=""
mount_point="/tmp/nanokvm-sd-root"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key-dir)
      key_dir="${2:?missing value for --key-dir}"
      shift 2
      ;;
    --label)
      label="${2:?missing value for --label}"
      shift 2
      ;;
    --host)
      host="${2:?missing value for --host}"
      shift 2
      ;;
    --port)
      port="${2:?missing value for --port}"
      shift 2
      ;;
    --timeout)
      timeout="${2:?missing value for --timeout}"
      shift 2
      ;;
    --ssh-host)
      ssh_host="${2:?missing value for --ssh-host}"
      shift 2
      ;;
    --root-part)
      root_part="${2:?missing value for --root-part}"
      shift 2
      ;;
    --mount-point)
      mount_point="${2:?missing value for --mount-point}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

ed_key="$key_dir/.ssh_host_ed25519_key"
rsa_key="$key_dir/.ssh_host_rsa_key"
generated_keys=()
sd_tmp_dir=""

generate_key() {
  local type="$1" path="$2" comment="$3"

  if [[ -s "$path" && -s "$path.pub" ]]; then
    return 0
  fi

  [[ "${NANOKVM_HOST_KEY_GENERATE:-1}" != 0 ]] \
    || die "missing $path and NANOKVM_HOST_KEY_GENERATE=0"

  log "generating host-$type key at $path"
  rm -f "$path" "$path.pub"
  case "$type" in
    ed25519) ssh-keygen -t ed25519 -N "" -C "$comment" -f "$path" -q ;;
    rsa) ssh-keygen -t rsa -b 4096 -N "" -C "$comment" -f "$path" -q ;;
    *) die "unsupported key type: $type" ;;
  esac

  generated_keys+=("$path" "$path.pub")
  if [[ -n "${SUDO_USER:-}" && "$(id -u)" = 0 ]]; then
    chown "$SUDO_USER" "$path" "$path.pub" 2>/dev/null || true
  fi
}

ensure_keys() {
  mkdir -p "$key_dir"
  chmod 700 "$key_dir"

  generate_key ed25519 "$ed_key" nanokvm-sops-host-key
  generate_key rsa "$rsa_key" nanokvm-host-key

  chmod 600 "$ed_key" "$rsa_key"
  chmod 644 "$ed_key.pub" "$rsa_key.pub"
}

cleanup_generated_keys() {
  if [[ -n "$sd_tmp_dir" ]]; then
    rm -rf "$sd_tmp_dir"
  fi

  if [[ "${NANOKVM_HOST_KEY_PERSIST:-1}" = 0 && "${#generated_keys[@]}" -gt 0 ]]; then
    log "NANOKVM_HOST_KEY_PERSIST=0; removing generated host-side keys"
    rm -f "${generated_keys[@]}"
  fi
}
trap cleanup_generated_keys EXIT

emit_install_commands() {
  local dest="$1"
  local dest_q
  dest_q="$(shell_quote "$dest")"

  printf '%s\n' "mkdir -p $dest_q"
  printf '%s\n' "umask 077"

  local file src tag target_q
  for file in \
    ssh_host_ed25519_key \
    ssh_host_ed25519_key.pub \
    ssh_host_rsa_key \
    ssh_host_rsa_key.pub
  do
    case "$file" in
      ssh_host_ed25519_key) src="$ed_key"; tag="__NANOKVM_KEY_ED25519__" ;;
      ssh_host_ed25519_key.pub) src="$ed_key.pub"; tag="__NANOKVM_KEY_ED25519_PUB__" ;;
      ssh_host_rsa_key) src="$rsa_key"; tag="__NANOKVM_KEY_RSA__" ;;
      ssh_host_rsa_key.pub) src="$rsa_key.pub"; tag="__NANOKVM_KEY_RSA_PUB__" ;;
      *) die "internal error: unexpected key file $file" ;;
    esac

    target_q="$(shell_quote "$dest/$file")"
    printf '%s\n' "cat > $target_q <<'$tag'"
    cat "$src"
    printf '%s\n' "$tag"
  done

  printf '%s\n' "chmod 600 $dest_q/ssh_host_ed25519_key $dest_q/ssh_host_rsa_key"
  printf '%s\n' "chmod 644 $dest_q/ssh_host_ed25519_key.pub $dest_q/ssh_host_rsa_key.pub"
}

wait_for_tcp() {
  local target_host="$1" target_port="$2" seconds="$3"
  local attempts=$((seconds * 2))

  for _ in $(seq 1 "$attempts"); do
    if timeout 1 bash -c ":</dev/tcp/$target_host/$target_port" 2>/dev/null; then
      return 0
    fi
    sleep 0.5
  done

  return 1
}

inject_live() {
  [[ -n "$host" ]] || die "inject-live requires --host"
  [[ -n "$port" ]] || die "inject-live requires --port"

  if [[ "${NANOKVM_HOST_KEY_GENERATE:-1}" = 0 ]]; then
    log "NANOKVM_HOST_KEY_GENERATE=0, skipping host-key push"
    return 0
  fi

  ensure_keys

  log "waiting for initrd debug shell on $host:$port"
  if ! wait_for_tcp "$host" "$port" "$timeout"; then
    log "WARN: debug shell never opened; skipping host-key push"
    return 0
  fi

  log "pushing host keys through initrd debug shell"
  if ! {
    printf '%s\n' "for i in \$(seq 1 120); do [ -d /sysroot/.rw-etc/upper ] && break; sleep 0.5; done"
    printf '%s\n' "if [ ! -d /sysroot/.rw-etc/upper ]; then echo HOSTKEY_NO_UPPER; exit 1; fi"
    emit_install_commands /sysroot/.rw-etc/upper/ssh
    printf '%s\n' "echo HOSTKEYS_INSTALLED"
    printf '%s\n' "exit"
  } | nc -w 20 "$host" "$port" 2>&1 \
    | sed -u "s/^/[$label] /" \
    | tee /tmp/nanokvm-hostkeys.log >/dev/null; then
    log "WARN: host-key push command failed; check /tmp/nanokvm-hostkeys.log"
  fi

  if grep -q HOSTKEYS_INSTALLED /tmp/nanokvm-hostkeys.log; then
    log "host keys installed; sshd-keygen will skip on device"
  else
    log "WARN: host-key push did not confirm; check /tmp/nanokvm-hostkeys.log"
  fi
}

inject_sd() {
  [[ -n "$ssh_host" ]] || die "inject-sd requires --ssh-host"
  [[ -n "$root_part" ]] || die "inject-sd requires --root-part"

  ensure_keys

  local mp_q part_q remote_script remote_script_q remote_command
  sd_tmp_dir="$(mktemp -d)"

  cp "$ed_key" "$sd_tmp_dir/ssh_host_ed25519_key"
  cp "$ed_key.pub" "$sd_tmp_dir/ssh_host_ed25519_key.pub"
  cp "$rsa_key" "$sd_tmp_dir/ssh_host_rsa_key"
  cp "$rsa_key.pub" "$sd_tmp_dir/ssh_host_rsa_key.pub"

  # This is remote shell source. The $1/$2 and $mp/$part expansions are
  # deliberately evaluated by the target, not by this host-side script.
  # shellcheck disable=SC2016
  remote_script='
mp=$1
part=$2
cleanup() { umount "$mp" 2>/dev/null || true; }
trap cleanup EXIT
umount "$mp" 2>/dev/null || true
mkdir -p "$mp"
mount "$part" "$mp"
install -d -m 0755 "$mp/etc/ssh"
tar -C "$mp/etc/ssh" -xf -
chown root:root \
  "$mp/etc/ssh/ssh_host_ed25519_key" \
  "$mp/etc/ssh/ssh_host_ed25519_key.pub" \
  "$mp/etc/ssh/ssh_host_rsa_key" \
  "$mp/etc/ssh/ssh_host_rsa_key.pub"
chmod 600 "$mp/etc/ssh/ssh_host_ed25519_key" "$mp/etc/ssh/ssh_host_rsa_key"
chmod 644 "$mp/etc/ssh/ssh_host_ed25519_key.pub" "$mp/etc/ssh/ssh_host_rsa_key.pub"
sync
'
  remote_script_q="$(shell_quote "$remote_script")"
  mp_q="$(shell_quote "$mount_point")"
  part_q="$(shell_quote "$root_part")"
  remote_command="sh -eu -c $remote_script_q sh $mp_q $part_q"

  log "installing SSH host keys on $ssh_host:$root_part"
  tar -C "$sd_tmp_dir" -cf "$sd_tmp_dir/host-keys.tar" \
    ssh_host_ed25519_key ssh_host_ed25519_key.pub \
    ssh_host_rsa_key ssh_host_rsa_key.pub

  # remote_command is constructed from shell-quoted local values above.
  # shellcheck disable=SC2029
  ssh "$ssh_host" "$remote_command" < "$sd_tmp_dir/host-keys.tar"

  log "installed SSH host keys on the SD root"
}

case "$mode" in
  recipient)
    ensure_keys
    ssh-to-age -i "$ed_key.pub"
    ;;
  inject-live)
    inject_live
    ;;
  inject-sd)
    inject_sd
    ;;
  *)
    usage
    exit 2
    ;;
esac
