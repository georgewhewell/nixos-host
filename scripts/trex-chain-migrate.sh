#!/usr/bin/env bash
# Copy the dormant chain data from bpool (HDD) to the nand4 btrfs subvolumes.
# Services are parked, so the sources are quiescent and a single pass suffices.
set -uo pipefail
LOG=/persist/chain-migration.log
exec >>"$LOG" 2>&1
echo "=== chain migration start $(date -Is)"
for c in monero tari p2pool; do
  echo "--- $c: $(du -sh /var/lib/$c 2>/dev/null | cut -f1)"
  rsync -aHAX --numeric-ids --info=progress2 "/var/lib/$c/" "/mnt/nand4-top/chains/$c/"
  echo "--- $c rc=$? done $(date -Is)"
done
echo "=== chain migration end $(date -Is)"
