#!/usr/bin/env nix-shell
#!nix-shell -i bash -p wireguard-tools qrencode jq sops
set -euo pipefail

script_dir="$(cd -- "$(dirname "$0")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
SOPS_CONFIG="${SOPS_CONFIG:-$repo_root/.sops.yaml}"
SOPS_FILE="${SOPS_FILE:-$repo_root/secrets/wireguard.yaml}"

usage() {
  echo "Usage: $0 <network> <peer> [output-dir]"
  echo ""
  echo "Generate WireGuard client configs with both split-tunnel and full-tunnel variants."
  echo ""
  echo "Arguments:"
  echo "  network     WireGuard network name (e.g., 'home')"
  echo "  peer        Peer name (e.g., 'ios', 'macbook')"
  echo "  output-dir  Directory to write configs (default: current directory)"
  echo ""
  echo "Example:"
  echo "  $0 home ios"
  echo "  $0 home macbook /tmp/wg-configs"
  exit 1
}

need_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing dependency: $1" >&2
    exit 1
  }
}

NETWORK="${1:-}"
PEER="${2:-}"
OUTPUT_DIR="${3:-.}"

if [ -z "$NETWORK" ] || [ -z "$PEER" ]; then
  usage
fi

need_bin nix

echo "Generating WireGuard configs for $NETWORK/$PEER..."

# Get config from Nix
echo "  Fetching network config from Nix..."
CONFIG=$(cd "$repo_root" && nix eval --json ".#nixosConfigurations.router.config.networking.wireguard-helpers.clientConfigData.${NETWORK}.${PEER}" 2>/dev/null) || {
  echo "error: Failed to get config for network '$NETWORK' peer '$PEER'" >&2
  echo "       Check that the network and peer exist in wireguard-helpers config." >&2
  exit 1
}

# Extract config values
ADDRESS=$(echo "$CONFIG" | jq -r '.address')
ADDRESS_V6=$(echo "$CONFIG" | jq -r '.addressV6 // empty')
DNS=$(echo "$CONFIG" | jq -r '.dns | join(", ")')
ENDPOINT=$(echo "$CONFIG" | jq -r '.endpoint')
KEEPALIVE=$(echo "$CONFIG" | jq -r '.persistentKeepalive // empty')
SPLIT_IPS=$(echo "$CONFIG" | jq -r '.splitAllowedIPs | join(", ")')
FULL_IPS=$(echo "$CONFIG" | jq -r '.fullAllowedIPs | join(", ")')

# Build address line
if [ -n "$ADDRESS_V6" ]; then
  ADDRESSES="$ADDRESS, $ADDRESS_V6"
else
  ADDRESSES="$ADDRESS"
fi

# Get secrets from sops
echo "  Fetching secrets from sops..."
ROUTER_PUB=$(SOPS_CONFIG="$SOPS_CONFIG" sops -d --extract '["wg-home-router-public"]' "$SOPS_FILE" 2>/dev/null) || {
  # Fall back to computing from private key
  ROUTER_PRIV=$(SOPS_CONFIG="$SOPS_CONFIG" sops -d --extract '["wg-home-router-private"]' "$SOPS_FILE")
  ROUTER_PUB=$(printf '%s' "$ROUTER_PRIV" | wg pubkey)
}

CLIENT_PRIV=$(SOPS_CONFIG="$SOPS_CONFIG" sops -d --extract "[\"wg-home-${PEER}-private\"]" "$SOPS_FILE") || {
  echo "error: Could not find private key for peer '$PEER' in sops." >&2
  echo "       Run: ./scripts/gen-wg.sh $PEER" >&2
  exit 1
}

PSK=$(SOPS_CONFIG="$SOPS_CONFIG" sops -d --extract "[\"wg-home-${PEER}-psk\"]" "$SOPS_FILE" 2>/dev/null || echo "")

# Build PresharedKey line if PSK exists
PSK_LINE=""
if [ -n "$PSK" ]; then
  PSK_LINE="PresharedKey = $PSK"
fi

# Build PersistentKeepalive line if set
KEEPALIVE_LINE=""
if [ -n "$KEEPALIVE" ] && [ "$KEEPALIVE" != "null" ]; then
  KEEPALIVE_LINE="PersistentKeepalive = $KEEPALIVE"
fi

# Create output directory if needed
mkdir -p "$OUTPUT_DIR"

# Generate split-tunnel config
SPLIT_CONF="$OUTPUT_DIR/${PEER}-split.conf"
cat > "$SPLIT_CONF" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $ADDRESSES
DNS = $DNS

[Peer]
PublicKey = $ROUTER_PUB
AllowedIPs = $SPLIT_IPS
Endpoint = $ENDPOINT
${PSK_LINE}
${KEEPALIVE_LINE}
EOF

# Clean up empty lines from optional fields
sed -i.bak '/^$/d' "$SPLIT_CONF" && rm -f "${SPLIT_CONF}.bak"

# Generate full-tunnel config
FULL_CONF="$OUTPUT_DIR/${PEER}-full.conf"
cat > "$FULL_CONF" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $ADDRESSES
DNS = $DNS

[Peer]
PublicKey = $ROUTER_PUB
AllowedIPs = $FULL_IPS
Endpoint = $ENDPOINT
${PSK_LINE}
${KEEPALIVE_LINE}
EOF

# Clean up empty lines
sed -i.bak '/^$/d' "$FULL_CONF" && rm -f "${FULL_CONF}.bak"

# Generate QR codes
echo "  Generating QR codes..."
qrencode -t PNG -o "$OUTPUT_DIR/${PEER}-split.png" < "$SPLIT_CONF"
qrencode -t PNG -o "$OUTPUT_DIR/${PEER}-full.png" < "$FULL_CONF"

echo ""
echo "Generated configs in $OUTPUT_DIR:"
echo "  ${PEER}-split.conf  - Split tunnel (routes: $SPLIT_IPS)"
echo "  ${PEER}-full.conf   - Full tunnel (routes: $FULL_IPS)"
echo "  ${PEER}-split.png   - QR code for split tunnel"
echo "  ${PEER}-full.png    - QR code for full tunnel"
echo ""
echo "=== SPLIT TUNNEL (${PEER}) ==="
qrencode -t ANSIUTF8 < "$SPLIT_CONF"
echo ""
echo "=== FULL TUNNEL (${PEER}) ==="
qrencode -t ANSIUTF8 < "$FULL_CONF"
