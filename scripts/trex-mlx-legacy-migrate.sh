#!/usr/bin/env bash
# trex: live migration from ConnectX-4 switchdev+OVS to plain legacy mode.
#
# WHY BY HAND: `switch-to-configuration switch` cannot do this alone. The
# eswitch mode is runtime state, set once in the initrd by a service this
# generation deletes -- deleting the service does not undo the mode. A plain
# switch would therefore leave a legacy-mode *config* on switchdev-mode
# *hardware*, and a switchdev PF has no verbs device, so the RDMA export would
# fail. Steps 2 and 3 below are the part NixOS cannot express.
#
# WHY DETACHED: step 1 destroys ovs-host, which holds 192.168.23.8 -- the
# address this SSH session arrives on. From step 1 until step 5 the host is
# unreachable. If this script were a child of sshd it would die mid-flight and
# strand the box with OVS down and nothing configured. Always run it via:
#
#   sudo systemd-run --unit=trex-mlx-migrate --collect \
#     --setenv=PATH=/run/current-system/sw/bin:/usr/bin:/bin \
#     /run/current-system/sw/bin/bash scripts/trex-mlx-legacy-migrate.sh
#
# RECOVERY: generation 26 is already the staged boot default and contains
# exactly this end state, so a power cycle is a clean recovery, not a loss.
# The log below lives on /persist, so it survives that reboot.
#
# NOT `set -e`: aborting halfway is the one outcome worse than any error here.
# Every step tolerates failure and the script always reaches step 5.
set -uo pipefail

TOPLEVEL="${TOPLEVEL:?set TOPLEVEL to the new system closure}"
PF=mlxlan0
PF_PCI=0000:41:00.0
LAN_CIDR=192.168.23.8/24
GATEWAY=192.168.23.1
LOG=/persist/mlx-migration.log

exec >>"$LOG" 2>&1
echo "================ migration start $(date -Is)"
echo "toplevel: $TOPLEVEL"
echo "before: $(ip -br addr show $PF 2>/dev/null)"
devlink dev eswitch show "pci/$PF_PCI" || true

# 0. Drop the NVMe-oF listener first so clients see a clean teardown rather
#    than a vanished target mid-IO.
echo "--- 0: stopping RDMA export"
systemctl stop spdk-models-export.service || true

# 1. Stop OVS. THE HOST LOSES ITS IP HERE.
echo "--- 1: stopping OVS (connectivity drops now)"
systemctl stop ovs-host-mtu.service ovs-hw-offload.service || true
systemctl stop ovs-mlx-netdev.service || true
systemctl stop ovs-vswitchd.service ovsdb.service || true

# 2. VFs must go before the eswitch can leave switchdev mode.
echo "--- 2: removing VFs"
echo 0 >"/sys/class/net/$PF/device/sriov_numvfs" 2>/dev/null || true
sleep 2

# 3. Back to legacy. This is what gives the PF its verbs device back.
echo "--- 3: eswitch -> legacy"
devlink dev eswitch set "pci/$PF_PCI" mode legacy || true
sleep 3

# 4. Activate the new generation: units, networkd config, the lot.
echo "--- 4: activating $TOPLEVEL"
nix-env -p /nix/var/nix/profiles/system --set "$TOPLEVEL" || true
"$TOPLEVEL/bin/switch-to-configuration" switch || true
# The dry run showed networkd would only be *reloaded*. A reload is a weak
# guarantee for a link that was an OVS port a moment ago; restart it outright.
systemctl restart systemd-networkd.service || true

# 5. Reachability backstop. If networkd has not addressed the PF, do it by
#    hand -- an unreachable box is the only unrecoverable outcome without OOB.
echo "--- 5: waiting for an address on $PF"
for _ in $(seq 1 30); do
  ip -4 -o addr show dev "$PF" | grep -q 'inet ' && break
  sleep 1
done
if ! ip -4 -o addr show dev "$PF" | grep -q 'inet '; then
  echo "!!! networkd did not address $PF; applying fallback"
  ip link set "$PF" up || true
  ip addr add "$LAN_CIDR" dev "$PF" || true
  ip route add default via "$GATEWAY" dev "$PF" || true
else
  echo "networkd addressed $PF normally"
fi

# 6. Bring storage back up on the PF's verbs device.
echo "--- 6: restarting RDMA export"
systemctl restart spdk-models-export.service || true

echo "--- result"
ip -br addr show "$PF"
devlink dev eswitch show "pci/$PF_PCI" || true
echo "verbs device: $(ls /sys/class/net/$PF/device/infiniband/ 2>/dev/null || echo NONE)"
ip -br link show | grep -c mlxlan0v && echo "^ VFs still present (expected 0)" || echo "no VFs (expected)"
systemctl is-active spdk-models-export.service systemd-networkd.service
echo "================ migration end $(date -Is)"
