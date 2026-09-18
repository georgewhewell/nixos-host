# Benchmark the USB transport between host and a running NanoKVM
# `boards.licheerv.mainline.live.*` stage 2.
#
# Run me as `nix run .#nanokvm-bench-usb-transport -- <label>`. The
# writeShellApplication wrapper provides jq, iperf3, fio, ping, and ssh
# from the runtime closure — there are NO `nix shell` calls in this
# script body, so the benchmark numbers don't include nix eval time.
#
# Usage:
#   nanokvm-bench-usb-transport <label>
# e.g. `nanokvm-bench-usb-transport ecm` then `nanokvm-bench-usb-transport rndis`.
set -euo pipefail

LABEL="${1:-unlabelled}"
TARGET=root@10.55.0.1
OUTDIR=/tmp/nanokvm-bench-${LABEL}-$(date +%H%M%S)
mkdir -p "$OUTDIR"

ssh_target() {
  ssh -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 \
      "$TARGET" "$@"
}

echo "==> [$LABEL] checking target ssh..."
ssh_target 'uname -r; cat /proc/cmdline | head -c 200; echo' | tee "$OUTDIR/uname.txt"

# Identify which transport is active by looking at the gadget on
# the device side. cdc_ether on host = ECM device-side; rndis_host on
# host = RNDIS device-side.
HOST_DRIVER=""
for d in /sys/class/net/*; do
  [ -r "$d/address" ] || continue
  mac=$(cat "$d/address" 2>/dev/null)
  if [ "$mac" = "02:1a:11:00:01:02" ]; then
    driver=$(readlink "$d/device/driver" 2>/dev/null | xargs basename 2>/dev/null)
    echo "==> [$LABEL] host iface $(basename "$d") driver=$driver"
    HOST_DRIVER="$driver"
  fi
done
echo "host_driver=$HOST_DRIVER" > "$OUTDIR/transport.txt"

echo "==> [$LABEL] starting iperf3 server on target..."
ssh_target 'pkill -9 iperf3 2>/dev/null; nohup iperf3 -s -D >/tmp/iperf3.log 2>&1; sleep 1'
sleep 1

echo "==> [$LABEL] iperf3 host->target TCP, 15s..."
iperf3 -c 10.55.0.1 -t 15 -i 5 -J > "$OUTDIR/iperf3-h2t-tcp.json" || true
TCP_H2T=$(jq -r '.end.sum_received.bits_per_second / 1e6 | floor' < "$OUTDIR/iperf3-h2t-tcp.json" 2>/dev/null || echo "?")
echo "    H->T TCP: ${TCP_H2T} Mbps"

echo "==> [$LABEL] iperf3 target->host TCP, 15s..."
iperf3 -c 10.55.0.1 -t 15 -i 5 -R -J > "$OUTDIR/iperf3-t2h-tcp.json" || true
TCP_T2H=$(jq -r '.end.sum_received.bits_per_second / 1e6 | floor' < "$OUTDIR/iperf3-t2h-tcp.json" 2>/dev/null || echo "?")
echo "    T->H TCP: ${TCP_T2H} Mbps"

echo "==> [$LABEL] iperf3 host->target UDP 20M, 10s..."
iperf3 -c 10.55.0.1 -t 10 -u -b 20M -i 5 -J > "$OUTDIR/iperf3-h2t-udp.json" || true

echo "==> [$LABEL] ping latency, 30 packets..."
ping -c 30 -q 10.55.0.1 | tail -3 | tee "$OUTDIR/ping.txt"

echo "==> [$LABEL] NBD seq read direct from /dev/nbd0 (fio 1M, 64MB, 15s)..."
# Drop caches first so we actually hit NBD, not page cache.
ssh_target 'echo 3 > /proc/sys/vm/drop_caches; fio --name=nbdread --filename=/dev/nbd0 \
  --rw=read --bs=1M --size=64M --direct=1 --iodepth=4 \
  --runtime=15 --time_based --group_reporting --output-format=json' \
  > "$OUTDIR/fio-nbd.json" 2>&1 || true
# fio prepends one info line before the JSON; skip until `^{`.
NBD_MBPS=$(sed -n '/^{/,$p' "$OUTDIR/fio-nbd.json" | jq -r '.jobs[0].read.bw_bytes / 1048576 | floor' 2>/dev/null || echo "?")
echo "    NBD read: ${NBD_MBPS} MB/s"

echo "==> [$LABEL] dmesg tail for transport errors..."
ssh_target 'dmesg | tail -20 | grep -iE "NETDEV WATCHDOG|transmit queue|cdc|rndis|usb 4340000" | tail -10' \
  > "$OUTDIR/target-dmesg.txt" || true
dmesg | tail -20 | grep -iE "cdc_ether|rndis_host|usb 3-4" | tail -10 > "$OUTDIR/host-dmesg.txt" || true

echo "==> [$LABEL] stopping iperf3 on target..."
ssh_target 'pkill -9 iperf3 2>/dev/null; true'

cat > "$OUTDIR/summary.txt" <<EOF
=== Benchmark: $LABEL ===
host_driver:    $HOST_DRIVER
TCP H->T:       ${TCP_H2T} Mbps
TCP T->H:       ${TCP_T2H} Mbps
NBD seq read:   ${NBD_MBPS} MB/s

Files in $OUTDIR:
$(ls -1 "$OUTDIR")
EOF
echo
cat "$OUTDIR/summary.txt"
echo
echo "Full data: $OUTDIR"
