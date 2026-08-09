# CRS510-8XS-2XQ "mikrotik-100g" (192.168.23.9) desired port state.
# Applied by scripts/mikrotik-100g-apply-config.
#
# Scope: physical port configuration (speed/FEC/flow-control) only. The
# defconf software bridge, interface lists, and the jumbo-mtu startup
# scheduler are left alone. Forced speeds MUST match the installed modules:
# the 2026-08-06 LAN outage was a stale forced-25G value on the CRS804 peer
# surviving an optic swap to 100G FR (symptom: good RX light, no-link).
#
# Cabling map (verified 2026-08-06; DAC ends share a vendor serial, so match
# `/interface ethernet monitor` sfp-vendor-serial against `ethtool -m`):
#   qsfp28-1 cage: Cisco-Innolight TR-FC13T-NCI 100G FR optic
#                  -> CRS804 "mikrotik-400g" qsfp56-dd-4-1 (fabric uplink)
#   qsfp28-2 cage: Luxshare 100G DAC -> trex
#   sfp28-1: HG GENUINE 25G BiDi LR (old direct router uplink, dark since the
#            CRS804 took over routing; defconf mgmt IP 192.168.23.9 is still
#            BOUND TO THIS PORT and only works via the bridge slave-IP quirk —
#            do not remove this port from the bridge without moving the IP)
#   sfp28-5: 5m OEM DAC SFP28-25G-CU5M (SN 2505080003) -> fuckup enp8s0f0np0
#   sfp28-7: 10G DAC (misc device)
#   sfp28-8: Mellanox 1m 25G DAC (spare; candidate replacement for sfp28-5)

# Fabric uplink to the CRS804: forced 100G, RS-FEC, no autonegotiation
# (matches the peer's forced 100G-baseSR4-LR4/fec91).
/interface ethernet set [find where name="qsfp28-1-1"] auto-negotiation=no speed=100G-baseCR4 fec-mode=fec91 mtu=9000 l2mtu=9000

# Trex 100G DAC: forced 100G, RS-FEC; global pause frames on (this hop
# carries the RoCE/NFS-RDMA fabric traffic and the CRS510 has no PFC support,
# so link-level flow control is the lossless mechanism here).
/interface ethernet set [find where name="qsfp28-2-1"] auto-negotiation=no speed=100G-baseCR4 fec-mode=fec91 rx-flow-control=on tx-flow-control=on mtu=9000 l2mtu=9000

# fuckup enp8s0f0np0 — TEMPORARY 10G DOWNGRADE (2026-08-06): the 5m OEM DAC
# stopped training at 25G on 2026-08-05 with every FEC/autoneg combination,
# even after a full NIC chip reset (mstfwreset -l 3) and a switch reboot, but
# links reliably at forced 10G. The cable is bad at 25G. After replacing the
# DAC (the 1m Mellanox in sfp28-8 is a known-good candidate), restore:
#   auto-negotiation=no speed=25G-baseCR fec-mode=fec91
# and mirror it on fuckup (ethtool autoneg off speed 25000 + fec rs — that
# side is runtime-only unless it has been moved into fuckup's NixOS config).
/interface ethernet set [find where name="sfp28-5"] auto-negotiation=no speed=10G-baseCR fec-mode=off rx-flow-control=on tx-flow-control=on mtu=9000 l2mtu=9000

# Old router BiDi uplink: keep the historical forced 25G/fec91 so the link
# self-restores if the BiDi pair is ever reconnected. Port is dark today but
# still carries the defconf mgmt IP binding (see header).
/interface ethernet set [find where name="sfp28-1"] auto-negotiation=no speed=25G-baseSR-LR fec-mode=fec91 mtu=9000 l2mtu=9000

:put "CRS510 declarative port configuration applied"
