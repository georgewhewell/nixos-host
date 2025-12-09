#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname "$0")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
SOPS_CONFIG="${SOPS_CONFIG:-$repo_root/.sops.yaml}"

SOPS_FILE="${SOPS_FILE:-secrets/wireguard.yaml}"
# Normalize to absolute so sops filename matching works with creation rules.
case "$SOPS_FILE" in
  /*) : ;;
  *) SOPS_FILE="$repo_root/$SOPS_FILE" ;;
esac
PEER="${1:-}"
if [ -z "$PEER" ]; then
  echo "usage: $0 <peer-name>" >&2
  exit 1
fi

need_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

need_bin sops
need_bin wg

# Ensure the SOPS file exists and is at least an empty YAML document.
# Ensure the SOPS file exists and has metadata; initialize if needed.
if ! SOPS_CONFIG="$SOPS_CONFIG" sops -d "$SOPS_FILE" >/dev/null 2>&1; then
  echo "{}" > "$SOPS_FILE"
  tmp=$(mktemp)
  SOPS_CONFIG="$SOPS_CONFIG" sops \
    --input-type yaml --output-type yaml \
    --encrypt "$SOPS_FILE" > "$tmp"
  mv "$tmp" "$SOPS_FILE"
fi

set_secret() {
  local path="$1" value="$2"
  # sops --set expects: '["key"] "value"'
  SOPS_CONFIG="$SOPS_CONFIG" sops -i --set "$path \"${value}\"" "$SOPS_FILE"
}

gen_peer() {
  local peer="$1"
  local priv pub psk
  priv=$(wg genkey)
  pub=$(printf '%s' "$priv" | wg pubkey)
  psk=$(wg genpsk)

  set_secret "[\"wg-home-${peer}-private\"]" "$priv"
  set_secret "[\"wg-home-${peer}-public\"]" "$pub"
  set_secret "[\"wg-home-${peer}-psk\"]" "$psk"

  echo "$peer:"
  echo "  public: $pub"
  echo "  psk:    $psk"
  echo
}

gen_peer "$PEER"

echo "Stored keys for \"$PEER\" (private + psk) in $SOPS_FILE."
echo "Only public key and PSK were echoed above; private is in SOPS."
