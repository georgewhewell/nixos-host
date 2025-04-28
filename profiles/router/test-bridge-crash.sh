#!/usr/bin/env bash

set -x

CONN_STR="ssh router.satanic.link"
VPPCTL_RUN="$CONN_STR sudo vppctl -s /run/vpp/main-cli.sock"

# Create a backup function to save log files
save_logs() {
    timestamp=$(date +%Y%m%d-%H%M%S)
    LOG_DIR="vpp-crash-logs-$timestamp"
    mkdir -p "$LOG_DIR"
    
    # Save journal logs
    $CONN_STR sudo journalctl -xeu vpp-main -n 1000 > "$LOG_DIR/vpp-journal.log"
    
    # Save dmesg
    $CONN_STR sudo dmesg > "$LOG_DIR/dmesg.log"
    
    # Check for core dump
    $CONN_STR ls -la /var/lib/systemd/coredump/ > "$LOG_DIR/coredump-list.txt"
    
    echo "Logs saved to $LOG_DIR"
}

# Setup trace before adding interfaces to bridge
echo "Setting up trace for bridge domain packets:"
$VPPCTL_RUN clear trace
$VPPCTL_RUN trace add bdcast-forward 100
$VPPCTL_RUN trace add l2-flood 100
$VPPCTL_RUN trace add dpdk-input 100
$VPPCTL_RUN trace add interface-output 100
$VPPCTL_RUN trace add l2-fwd 100
$VPPCTL_RUN trace add ip4-input 100

# Set the debug flag on some components 
$VPPCTL_RUN set logging class l2 debug
$VPPCTL_RUN set logging class dpdk debug

# Show initial state
echo "Initial interface state:"
$VPPCTL_RUN show int
$VPPCTL_RUN show bridge-domain

# First, enable just a single 2.5G interface to isolate the issue
echo "Enabling lan2 interface and adding to bridge domain..."
$VPPCTL_RUN set interface state lan2 up
sleep 1
$VPPCTL_RUN show int

echo "Adding lan2 to bridge domain..."
$VPPCTL_RUN set interface l2 bridge lan2 1

# Wait and monitor for crash
echo "Monitoring for crash (waiting 30 seconds)..."
for i in {1..30}; do
    sleep 1
    # Check if VPP is still running
    VPP_STATUS=$($CONN_STR "systemctl is-active vpp-main || echo failed")
    if [[ "$VPP_STATUS" == "failed" ]]; then
        echo "VPP crashed! Saving logs..."
        save_logs
        exit 1
    fi
    # Show trace periodically 
    if [[ $((i % 5)) -eq 0 ]]; then
        echo "Trace buffer at $i seconds:"
        $VPPCTL_RUN show trace || echo "Failed to get trace, VPP may have crashed"
    fi
done

# If we got here, try adding another interface
echo "No crash detected. Adding lan3 to bridge domain..."
$VPPCTL_RUN set interface state lan3 up
sleep 1
$VPPCTL_RUN set interface l2 bridge lan3 1

# Wait and monitor for crash
echo "Monitoring for crash (waiting 30 more seconds)..."
for i in {1..30}; do
    sleep 1
    # Check if VPP is still running
    VPP_STATUS=$($CONN_STR "systemctl is-active vpp-main || echo failed")
    if [[ "$VPP_STATUS" == "failed" ]]; then
        echo "VPP crashed after adding lan3! Saving logs..."
        save_logs
        exit 1
    fi
    # Show trace periodically 
    if [[ $((i % 5)) -eq 0 ]]; then
        echo "Trace buffer at $i seconds:"
        $VPPCTL_RUN show trace || echo "Failed to get trace, VPP may have crashed"
    fi
done

echo "No crash detected. Test completed."
# Get final state
$VPPCTL_RUN show int
$VPPCTL_RUN show bridge-domain
$VPPCTL_RUN show l2fib

# Cleanup - remove the interfaces from the bridge
echo "Cleaning up - removing interfaces from bridge"
$VPPCTL_RUN set interface l2 bridge lan2 1 disable
$VPPCTL_RUN set interface l2 bridge lan3 1 disable
$VPPCTL_RUN set interface state lan2 down
$VPPCTL_RUN set interface state lan3 down

echo "Test complete."