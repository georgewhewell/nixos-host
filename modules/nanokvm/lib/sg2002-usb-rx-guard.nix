{ lib }:
{
  busybox,
  hostIp,
  requireCarrier ? false,
  initialDelaySec ? 0,
}:
''
  set -u
  BB=${lib.escapeShellArg busybox}
  G=/sys/kernel/config/usb_gadget/sg2002
  stat=/sys/class/net/usb0/statistics
  stale=0
  last_udc=""

  ${lib.optionalString (initialDelaySec > 0) ''
    "$BB" sleep ${toString initialDelaySec}
  ''}
  echo "usb-rx-guard: monitoring usb0" > /dev/kmsg
  while :; do
    "$BB" sleep 2
    [ -d "$stat" ] || continue
    ${lib.optionalString requireCarrier ''
      carrier=$("$BB" cat /sys/class/net/usb0/carrier 2>/dev/null || echo 0)
      if [ "$carrier" != 1 ]; then
        stale=0
        continue
      fi
    ''}
    rx1=$("$BB" cat "$stat/rx_packets" 2>/dev/null || echo 0)
    tx1=$("$BB" cat "$stat/tx_packets" 2>/dev/null || echo 0)
    # Force one target-to-host packet into each sample window. Never wait
    # synchronously for the probe: a wedged USB netdev syscall must not keep
    # the independent guard from reaching the controller recovery path.
    "$BB" ping -c 1 -W 1 ${lib.escapeShellArg hostIp} >/dev/null 2>&1 &
    probe_pid=$!
    "$BB" sleep 2
    rx2=$("$BB" cat "$stat/rx_packets" 2>/dev/null || echo 0)
    tx2=$("$BB" cat "$stat/tx_packets" 2>/dev/null || echo 0)
    "$BB" kill "$probe_pid" >/dev/null 2>&1 || true

    # A transmitted probe with no receive progress is the observed SG2002
    # DWC2 bulk-OUT failure signature. Require it twice to ignore packet loss.
    if [ "$tx1" != "$tx2" ] && [ "$rx1" = "$rx2" ]; then
      stale=$((stale + 1))
      echo "usb-rx-guard: probe produced no RX, rx=$rx1->$rx2 tx=$tx1->$tx2 stale=$stale" > /dev/kmsg
    else
      stale=0
    fi
    if [ "$stale" -lt 2 ]; then
      continue
    fi

    stale=0
    current_udc=$("$BB" cat "$G/UDC" 2>/dev/null || true)
    [ -z "$current_udc" ] || last_udc=$current_udc
    udc=$last_udc
    driver=/sys/bus/platform/drivers/dwc2
    echo "usb-rx-guard: usb0 probe and RX stuck; re-probing dwc2 ($udc)" > /dev/kmsg
    [ -n "$udc" ] || continue
    echo "" > "$G/UDC" 2>/dev/null || true
    if [ ! -e "$driver/unbind" ] || [ ! -e "$driver/bind" ]; then
      echo "usb-rx-guard: dwc2 platform driver controls are missing" > /dev/kmsg
      echo "$udc" > "$G/UDC" 2>/dev/null || true
      continue
    fi
    if ! echo "$udc" > "$driver/unbind" 2>/dev/null; then
      echo "usb-rx-guard: failed to unbind dwc2 ($udc)" > /dev/kmsg
      echo "$udc" > "$G/UDC" 2>/dev/null || true
      continue
    fi
    "$BB" sleep 1
    if ! echo "$udc" > "$driver/bind" 2>/dev/null; then
      echo "usb-rx-guard: failed to bind dwc2 ($udc)" > /dev/kmsg
      continue
    fi

    # UDC registration is asynchronous after a platform-driver rebind.
    ready=0
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      if [ -e "/sys/class/udc/$udc" ]; then
        ready=1
        break
      fi
      "$BB" sleep 0.1
    done
    if [ "$ready" = 1 ] && echo "$udc" > "$G/UDC" 2>/dev/null; then
      echo "usb-rx-guard: dwc2 and gadget rebound ($udc)" > /dev/kmsg
    else
      echo "usb-rx-guard: dwc2 re-probe failed ($udc)" > /dev/kmsg
    fi
  done
''
