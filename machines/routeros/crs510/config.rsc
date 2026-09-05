# CRS510-8XS-2XQ "mikrotik-crs510" (192.168.23.9) desired port state.
# Applied by scripts/mikrotik-crs510-apply-config.
#
# Scope: the defconf software bridge's MLAG setting plus physical port
# configuration (speed/FEC). Interface lists and the jumbo-mtu startup
# scheduler are left alone.
#
# Cabling map (verified 2026-08-14; DAC ends share a vendor serial, so match
# `/interface ethernet monitor` sfp-vendor-serial against `ethtool -m`):
#   qsfp28-1 cage: Luxshare 100G DAC -> CRS804 "mikrotik-crs804" cage 2
#                  (re-cabled 2026-08-15; this was trex's port. It is now this
#                  switch's ONLY fabric uplink -- everything beyond the CRS804
#                  is reached through it)
#   qsfp28-2 cage: empty since 2026-08-15. The Cisco-Innolight TR-FC13T-NCI
#                  100G FR optic that reached the CRS812 moved to CRS804
#                  cage 1; the CRS812 now sits two hops away behind the CRS804.
#   sfp28-1: HG GENUINE 25G BiDi LR (old direct router uplink; the defconf
#            mgmt IP 192.168.23.9 is BOUND TO THIS PORT and works only via
#            the bridge slave-IP quirk — do not remove it from the bridge
#            without moving the IP first)
#   sfp28-5: empty spare (held the 5m OEM DAC that failed at 25G, see below)
#   sfp28-7: 10G DAC -> CRS804 ether1, the CRS804's OOB management lifeline.
#            After the re-cable this is a second path to the same switch, so
#            RSTP blocks one of the two; the 100G qsfp28-1 leg should win on
#            path cost. Do not treat a blocking sfp28-7 as a fault.
#   sfp28-8: Mellanox 1m DAC SFP28-25G-1M (SN S230205230003)
#            -> fuckup enp8s0f1np1 (NIC port 2)

# Match the DNS name: the switches are named for their board, not their link
# speed (2026-08-15). The old mikrotik-100g name remains an alias in
# network.nix, so nothing that still uses it breaks.
/system identity set name="mikrotik-crs510"

# CRITICAL: defconf ships this bridge with mlag-peer-port=sfp28-8. With no
# MLAG peer connected, RouterOS marks that bridge port INACTIVE (";;; mlag
# not connected") — the cage trains a perfectly good link at full speed and
# then forwards nothing at all. This cost an afternoon on 2026-08-06 when
# fuckup's replacement DAC was moved into sfp28-8. Keep MLAG cleared unless a
# real peer switch is deployed.
/interface bridge set [find where name="bridge"] mlag-peer-port=none

# Fabric uplink to the CRS804 (this was trex's DAC until the 2026-08-15
# re-cable). Forced 100G CR4 with RS-FEC, matching cage 2 on the peer. Global
# pause on: this leg now carries fuckup's RoCE/NFS-RDMA traffic through to
# trex, the CRS510 has no PFC support, and the peer runs PFC on TC3 — the same
# pause-against-PFC pairing this port's predecessor ran to the CRS812.
/interface ethernet set [find where name="qsfp28-1-1"] auto-negotiation=no speed=100G-baseCR4 fec-mode=fec91 rx-flow-control=on tx-flow-control=on mtu=9000 l2mtu=9000

# qsfp28-2 — empty since the FR optic moved to CRS804 cage 1. Keep the forced
# 100G SR4/LR4 + fec91 so the link self-restores if a 100G FR pair is ever
# plugged back in here, the same way sfp28-1 holds the old BiDi settings.
/interface ethernet set [find where name="qsfp28-2-1"] auto-negotiation=no speed=100G-baseSR4-LR4 fec-mode=fec91 rx-flow-control=on tx-flow-control=on mtu=9000 l2mtu=9000

# fuckup enp8s0f1np1 — thermally safe 10G fallback over the 1m Mellanox DAC.
# On 2026-08-14 both ConnectX-4 Lx sensors reached 95-96C and the kernel raised
# mlx5 high-temperature warnings: 25G would no longer train after the switch
# reboot, while forced 10G CR came up immediately and remained stable. Restore
# 25G only after fixing airflow and verifying the mlx5 sensors stay cool.
/interface ethernet set [find where name="sfp28-8"] auto-negotiation=no speed=10G-baseCR fec-mode=off rx-flow-control=on tx-flow-control=on mtu=9000 l2mtu=9000

# sfp28-5 — empty spare, held back at autonegotiation defaults. The 5m OEM
# DAC (SFP28-25G-CU5M, SN 2505080003) that lived here refused to train at 25G
# under every FEC/autoneg combination, survived a NIC chip reset and a switch
# reboot, and linked only at 10G. Treat that cable as scrap.
/interface ethernet set [find where name="sfp28-5"] auto-negotiation=yes fec-mode=auto mtu=9000 l2mtu=9000

# Old router BiDi uplink: keep the historical forced 25G/fec91 so the link
# self-restores if the BiDi pair is ever reconnected.
/interface ethernet set [find where name="sfp28-1"] auto-negotiation=no speed=25G-baseSR-LR fec-mode=fec91 mtu=9000 l2mtu=9000

# RouterOS can leave a port in a stale ASIC offload group after link
# retraining or an MLAG/bridge change: the bridge reports forwarding and H,
# yet frames reach only the switch CPU and the host is unreachable. Rebinding
# the port once repairs the group; the persistent state stays offloaded.
# (Same workaround as the CRS804 config. Required on 2026-08-06 for sfp28-8.)
:foreach p in={"qsfp28-1-1";"qsfp28-2-1";"sfp28-8"} do={
    :local bp [/interface bridge port find where interface=$p]
    :if ([:len $bp] > 0) do={
        /interface bridge port set $bp hw=no
        :delay 500ms
        /interface bridge port set $bp hw=yes
    }
}

:put "CRS510 declarative port configuration applied"
