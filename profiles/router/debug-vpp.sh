#!/usr/bin/env bash

set -euo pipefail

CONN_STR="ssh 10.86.167.2"

echo "Getting VPP Configs"

CONFIG_PATH=$($CONN_STR systemctl cat vpp-main | grep "vpp -c" | cut -d ' ' -f3)

echo "Config path is $CONFIG_PATH"

CONFIG_CONTENTS=$($CONN_STR cat $CONFIG_PATH)

echo "Config: $CONFIG_CONTENTS"

STARTUP_PATH=$($CONN_STR cat $CONFIG_PATH | grep "startup-config" | cut -d ' ' -f4)

echo "Startup path: $STARTUP_PATH"

STARTUP_CONFIG=$($CONN_STR cat $STARTUP_PATH)

echo "Startup: $STARTUP_CONFIG"

LATEST_JOURNAL=$($CONN_STR sudo journalctl -xeu vpp-main)

echo "Latest journalctl: $LATEST_JOURNAL"

VPPCTL_RUN="$CONN_STR sudo vppctl -s /run/vpp/main-cli.sock"

VPPCTL_SHOW_INT=$($VPPCTL_RUN show int)

echo "vpp int: $VPPCTL_SHOW_INT"

VPPCTL_SHOW_HW_INT=$($VPPCTL_RUN show hardware-interfaces)

echo "vpp hw int: $VPPCTL_SHOW_HW_INT"

echo "Getting bridge domain information:"
BRIDGE_INFO=$($VPPCTL_RUN show bridge-domain)
echo "Bridge domain info:"
echo "$BRIDGE_INFO"

echo "Getting trace buffer information:"
echo "Trace buffer info:"
$VPPCTL_RUN show trace

echo "Getting error counters:"
echo "Error counters:"
$VPPCTL_RUN show errors

echo "Getting interface counters:"
echo "Interface counters:"
$VPPCTL_RUN show interface counters

echo "Getting bridge MAC addresses:"
echo "Bridge MACs:"
$VPPCTL_RUN show l2fib

echo "Getting available cores and thread info:"
echo "Core info:"
$VPPCTL_RUN show threads

echo "Getting node statistics:"
echo "Node stats:"
$VPPCTL_RUN show node counters

echo "Setting up trace for future debugging:"
$VPPCTL_RUN clear trace
$VPPCTL_RUN trace add bdcast-forward 50
$VPPCTL_RUN trace add l2-flood 50
$VPPCTL_RUN trace add dpdk-input 50
$VPPCTL_RUN trace add interface-output 50
$VPPCTL_RUN trace add l2-fwd 50
echo "Trace configured for bridge packets"

# Get memory usage information
echo "Getting memory heap information:"
$VPPCTL_RUN show memory main-heap

# Check for any buffer information
echo "Getting buffer information:"
$VPPCTL_RUN show buffers

# Get node counters that might show drops
echo "Getting node counters with errors:"
$VPPCTL_RUN show node counters | grep -i error

# Get L2 specific configuration
echo "Getting L2 bridge configuration:"
$VPPCTL_RUN show bridge-domain detail
