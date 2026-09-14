#!/usr/bin/env bash
# trex root migration (2026-08-08): move the `nix` subvolume from the 212G
# Optane pair (`trexroot`) to the 4x Corsair array (`nand4`), and break the
# /persist holdall into per-service named subvolumes on `trexroot`.
#
# The Optanes keep the ESPs and all the small, latency-sensitive service
# state; only the Nix store leaves. Run phases in order:
#
#   bulk        live, no downtime  -- full send of trexroot/nix -> nand4
#   state-seed  live, no downtime  -- copy /persist/* into trexroot/state/*
#   delta       cutover            -- incremental nix send (AFTER the build)
#   state-sync  cutover            -- rsync deltas into the state subvolumes
#   promote     cutover            -- make nand4/nix writable, ready to boot
#   status      any time           -- where things stand
#
# Rollback: trexroot/nix is never touched. Every pre-existing generation's
# initrd still names /dev/disk/by-label/trexroot for /nix, so the ESP boot
# menu remains a working escape hatch until you destroy it by hand.
set -euo pipefail

TREX_TOP=/mnt/trexroot-top
NAND_TOP=/mnt/nand4-top
SNAP1=.snap-nix-1   # bulk baseline, kept as the parent for the incremental
SNAP2=.snap-nix-2   # cutover delta

# Mirrors environment.persistence."/persist".directories in
# machines/x86/trex/default.nix. Keep the two in step.
STATE_DIRS=(
  /var/lib/acme
  /var/lib/kimi-certs
  /var/lib/samba
  /var/lib/nfs
  /var/lib/syncoid
  /var/lib/rasdaemon
  /var/lib/fwupd
  /var/lib/boltd
  /var/lib/krb5kdc
  /var/lib/docker
  /var/lib/autobrr
  /var/lib/radarr
  /var/lib/sonarr
  /var/lib/grafana
  /var/lib/postgresql
  /var/lib/OpenRGB
  /var/lib/qui
  /var/lib/systemd/linger
  /var/lib/jellyfin
  /var/lib/private/hellas
  /var/lib/nixos
  /root/.config/gcloud
  /var/log/journal
  /var/log/netconsole
)

log() { printf '\n=== %s\n' "$*"; }

need_root() {
  [ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
}

mount_tops() {
  mkdir -p "$TREX_TOP" "$NAND_TOP"
  mountpoint -q "$TREX_TOP" || \
    mount -o subvolid=5,noatime /dev/disk/by-label/trexroot "$TREX_TOP"
  mountpoint -q "$NAND_TOP" || \
    mount -o subvolid=5,noatime /dev/disk/by-label/nand4 "$NAND_TOP"
}

phase_bulk() {
  mount_tops
  if [ -e "$NAND_TOP/$SNAP1" ]; then
    log "nand4/$SNAP1 already present -- bulk pass already done"
    return 0
  fi
  [ -e "$TREX_TOP/$SNAP1" ] || \
    btrfs subvolume snapshot -r "$TREX_TOP/nix" "$TREX_TOP/$SNAP1"
  # Settle the snapshot before send, or send races the commit.
  btrfs subvolume sync "$TREX_TOP"

  log "full send trexroot/$SNAP1 -> nand4 (~65G on disk, millions of files)"
  btrfs send "$TREX_TOP/$SNAP1" | btrfs receive "$NAND_TOP/"
  log "bulk pass complete"
}

phase_state_seed() {
  mount_tops
  mkdir -p "$TREX_TOP/state"
  for dir in "${STATE_DIRS[@]}"; do
    # /var/lib/private/hellas -> state/var/lib/private/hellas
    target="$TREX_TOP/state$dir"
    src="/persist$dir"
    if [ ! -d "$src" ]; then
      log "skip $dir (absent from /persist)"
      continue
    fi
    if [ -e "$target" ]; then
      log "skip $dir (state subvolume exists)"
      continue
    fi
    mkdir -p "$(dirname "$target")"
    btrfs subvolume create "$target"
    chown --reference="$src" "$target"
    chmod --reference="$src" "$target"
    log "seeding $dir"
    rsync -aHAX --numeric-ids --info=stats2 "$src"/ "$target"/
  done
  log "state seed complete"
}

phase_delta() {
  mount_tops
  [ -e "$NAND_TOP/$SNAP1" ] || { echo "run the bulk phase first" >&2; exit 1; }
  [ -e "$TREX_TOP/$SNAP2" ] && btrfs subvolume delete "$TREX_TOP/$SNAP2" || true
  [ -e "$NAND_TOP/$SNAP2" ] && btrfs subvolume delete "$NAND_TOP/$SNAP2" || true

  # The store must be quiescent: the sqlite db in /nix/var/nix must be
  # captured consistently, and anything written after this point is lost.
  systemctl stop nix-daemon.socket nix-daemon.service || true
  sync
  btrfs subvolume snapshot -r "$TREX_TOP/nix" "$TREX_TOP/$SNAP2"
  btrfs subvolume sync "$TREX_TOP"

  log "incremental send $SNAP1..$SNAP2 -> nand4"
  btrfs send -p "$TREX_TOP/$SNAP1" "$TREX_TOP/$SNAP2" | btrfs receive "$NAND_TOP/"
  log "delta complete"
}

phase_state_sync() {
  mount_tops
  for dir in "${STATE_DIRS[@]}"; do
    target="$TREX_TOP/state$dir"
    src="/persist$dir"
    [ -d "$src" ] && [ -d "$target" ] || continue
    log "syncing $dir"
    rsync -aHAX --numeric-ids --delete "$src"/ "$target"/
  done
  log "state sync complete"
}

phase_promote() {
  mount_tops
  [ -e "$NAND_TOP/$SNAP2" ] || { echo "run the delta phase first" >&2; exit 1; }
  if [ -e "$NAND_TOP/nix" ]; then
    log "nand4/nix exists -- refusing to clobber; delete it by hand if stale"
    exit 1
  fi
  btrfs subvolume snapshot "$NAND_TOP/$SNAP2" "$NAND_TOP/nix"
  btrfs subvolume sync "$NAND_TOP"
  log "nand4/nix is writable and ready; reboot into the new generation"
}

phase_status() {
  mount_tops
  log "trexroot"
  btrfs filesystem usage "$TREX_TOP" | head -12
  btrfs subvolume list "$TREX_TOP"
  log "nand4"
  btrfs filesystem usage "$NAND_TOP" | head -12
  btrfs subvolume list "$NAND_TOP"
}

need_root
case "${1:-status}" in
  bulk)       phase_bulk ;;
  state-seed) phase_state_seed ;;
  delta)      phase_delta ;;
  state-sync) phase_state_sync ;;
  promote)    phase_promote ;;
  status)     phase_status ;;
  *) echo "usage: $0 {bulk|state-seed|delta|state-sync|promote|status}" >&2; exit 1 ;;
esac
