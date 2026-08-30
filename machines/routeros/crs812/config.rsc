# CRS812-8DS-2DQ-2DDQ "mikrotik-crs812" desired initial state.
# Applied by scripts/mikrotik-crs812-apply-config.
#
# This is intentionally a conservative first adoption. The factory bridge is
# retained as the single hardware-offloaded L2 domain and VLAN filtering stays
# disabled until the remaining 50/200G cabling map is known. Untagged LAN
# and fabric IPv4 subnets therefore coexist on this bridge, matching the old
# CRS804's physical fabric domain, while tagged VLAN 50 crosses transparently.

/system identity set name="mikrotik-crs812"
/system package update set channel=testing

# All switch-chip ports support the fabric jumbo MTU. A 1500-byte peer on a
# copper port still exchanges ordinary frames normally; setting the port's
# ceiling higher prevents it from pinning the bridge and routed fabric to 1500.
:foreach p in={"ether1";"ether2"} do={
    /interface ethernet set [find where name=$p] mtu=9000 l2mtu=9216
}
:foreach p in=[/interface ethernet find where name~"^(qsfp56|sfp56)"] do={
    /interface ethernet set $p mtu=9000 l2mtu=9216
}

# One bridge is the hardware-offload path on the 98DX7335. Do not split ports
# across multiple bridges: only one bridge can retain full switch-chip offload.
/interface bridge set [find where name="bridge"] protocol-mode=rstp vlan-filtering=no auto-mac=no admin-mac=38:32:7A:14:FF:67 mtu=9000 comment="nixos-config: hardware fabric bridge"

# BlueField-2 p0: HELLAS serial 2606180004 in the first 200G-capable QSFP56
# cage. Despite the vendor part number, both endpoints decode it as a QSFP28
# 100GBASE-CR4 cable. Force four-lane 100G with RS-FEC to match the DPU; 200G
# or an ambiguous speed-only setting leaves the link at NO-CARRIER.
/interface ethernet set [find where name="qsfp56-1-1"] disabled=no auto-negotiation=no speed=100G-baseCR4 fec-mode=fec91 mtu=9000 l2mtu=9216 comment="nixos-config: bluefield2 p0 100G lab"

# CRS804 cage 1 (qsfp56-dd-1-1) <-> CRS812 qsfp56-2-1: matched Cisco-Innolight
# TR-FC13T-NCI 100G FR optics (INL255000CT / INL255000RB). Both ends require
# forced SR4/LR4 with RS-FEC; optical power and EEPROM checks are healthy.
# Re-cabled 2026-08-15: the far end moved off CRS510 qsfp28-2-1 to the CRS804,
# which is now the hub. THIS IS THIS SWITCH'S ONLY UPLINK — the fabric gateway
# 192.168.25.1 and every strix node behind this switch depend on it.
/interface ethernet set [find where name="qsfp56-2-1"] disabled=no auto-negotiation=no speed=100G-baseSR4-LR4 fec-mode=fec91 mtu=9000 l2mtu=9216

# DDQ cage 2 holds a Dell EMC C0TP5 400G-to-4x100G copper breakout
# (CN0F9KR711M0020). Each 100G-baseCR2 link begins on an odd-numbered
# interface and consumes the following lane. RouterOS therefore configures
# 1/3/5/7 and requires the companion 2/4/6/8 interfaces to remain enabled.
# 100G CR2 requires RS-FEC and forced speed on this switch.
#
# The strix machines have ONE fabric port each: a single-port SharedIO mlx5 on
# one M.2, with the other M.2 carrying PCIe x4 to a PLX that fans out to 4x
# V620 GPUs and the BlueField-2. The old "fabric1" second rail on cage 1 does
# not exist any more — do not restore those four 100G entries.
# strix-1 exception (2026-08-26): a ConnectX-7 now sits in strix-1's M.2 and
# is cabled to a cage-1 200G branch. Whether the SharedIO mlx5 behind
# qsfp56-dd-2-1 was displaced by it is not yet confirmed; the 100G stanza is
# kept so the port keeps linking if the CX5 is still present.
:foreach p in={"qsfp56-dd-2-1";"qsfp56-dd-2-3";"qsfp56-dd-2-5";"qsfp56-dd-2-7"} do={
    /interface ethernet set [find where name=$p] disabled=no auto-negotiation=no speed=100G-baseCR2 fec-mode=fec91 mtu=9000 l2mtu=9216
}
:foreach p in={"qsfp56-dd-2-2";"qsfp56-dd-2-4";"qsfp56-dd-2-6";"qsfp56-dd-2-8"} do={
    /interface ethernet set [find where name=$p] disabled=no mtu=9000 l2mtu=9216
}
/interface ethernet set [find where name="qsfp56-dd-2-1"] comment="nixos-config: fabric strix-1 (cx5; possibly displaced by the cage-1 cx7, 2026-08-26)"
/interface ethernet set [find where name="qsfp56-dd-2-3"] comment="nixos-config: fabric strix-2"
/interface ethernet set [find where name="qsfp56-dd-2-5"] comment="nixos-config: fabric spare"
/interface ethernet set [find where name="qsfp56-dd-2-7"] comment="nixos-config: fabric strix-4"

# DDQ cage 1 now holds an OEM QDD-2x200G-CU1M passive breakout (1m, SN
# 2605280004) instead of the Dell 4x100G one. It is a 400G DD end fanning out
# to two 200G QSFP56 branches, so the lane layout is different: two four-lane
# primaries (-1 and -5) with 2/3/4 and 6/7/8 kept enabled as their members.
#
# Cabling map (2026-08-26): one branch is the BlueField-2 in strix-2's
# chassis — DPU enp3s0np0 b8:ce:f6:f8:d7:ac / fabric 192.168.25.22, and since
# the CX5's pending LINK_TYPE=IB flip took its netdevs on 2026-08-26 this
# same port also carries strix-2's host fabric 192.168.25.102
# (b8:ce:f6:f8:d7:aa) — verified live: strix-2 pings trex's fabric addresses
# at 200G. The formerly spare branch was plugged into strix-1's new
# ConnectX-7 (M.2 slot) the same day. Both primaries are configured
# identically, so it does not matter which physical branch each host sits on
# and no switch-side split/enable step is needed for the second leg.
#
# 200G CR4 is PAM4 and needs RS-FEC, selected by fec-mode=auto — this mirrors
# the stanza the DPU linked under when this same splitter lived in CRS804
# cage 1. The DPU forces the matching mode from its side (AutoNegotiation
# false / 200G in machines/aarch64/bluefield2/default.nix); with no partner it
# reports "No partner detected during force mode" and stays NO-CARRIER, which
# is exactly how 192.168.25.22 went missing. The strix-1 ConnectX-7 must
# force the same 200G/RS-FEC mode from its side, or link exactly the way the
# working strix-2 leg does if it autonegotiates against this forced port.
:foreach p in={"qsfp56-dd-1-1";"qsfp56-dd-1-5"} do={
    /interface ethernet set [find where name=$p] disabled=no auto-negotiation=no speed=200G-baseCR4 fec-mode=auto mtu=9000 l2mtu=9216
}
:foreach p in={"qsfp56-dd-1-2";"qsfp56-dd-1-3";"qsfp56-dd-1-4";"qsfp56-dd-1-6";"qsfp56-dd-1-7";"qsfp56-dd-1-8"} do={
    /interface ethernet set [find where name=$p] disabled=no mtu=9000 l2mtu=9216
}
/interface ethernet set [find where name="qsfp56-dd-1-1"] comment="nixos-config: 200G branch A (strix-2 bluefield2 or strix-1 cx7)"
/interface ethernet set [find where name="qsfp56-dd-1-5"] comment="nixos-config: 200G branch B (strix-2 bluefield2 or strix-1 cx7)"

# Keep every factory bridge member hardware-offloaded. The uplink carries both
# untagged LAN/fabric traffic and tagged VLAN 50 without filtering.
:foreach bp in=[/interface bridge port find where bridge="bridge"] do={
    /interface bridge port set $bp hw=yes pvid=1 ingress-filtering=yes frame-types=admit-all
}

# Test-only router-on-a-stick path from the CRS804 uplink to BlueField.  VLAN
# filtering is not enabled on this adoption bridge yet, so this row is staged
# policy rather than an active restriction; it becomes the narrow allow-list
# when filtering is enabled later.
/interface bridge vlan remove [find where comment="nixos-config: VPP lab VLANs"]
/interface bridge vlan add bridge="bridge" vlan-ids=3901-3903 tagged=qsfp56-dd-1-1,qsfp56-1-1 comment="nixos-config: VPP lab VLANs"

# Static management and fabric gateway addresses. The factory 192.168.88.1 is
# retained on this bridge as a local recovery address.
:if ([:len [/ip address find where comment="nixos-config-lan-mgmt"]] = 0) do={
    /ip address add address=192.168.23.27/24 interface="bridge" comment="nixos-config-lan-mgmt"
}
:if ([:len [/ip address find where comment="nixos-config: fabric gateway"]] = 0) do={
    /ip address add address=192.168.25.1/24 interface="bridge" comment="nixos-config: fabric gateway"
}

# Fixed fabric members get static neighbours so L3HW starts deterministically.
/ip arp remove [find where address=192.168.25.22 and interface="bridge"]
/ip arp add address=192.168.25.22 mac-address=B8:CE:F6:F8:D7:AC interface="bridge" comment="nixos-config: bluefield2 fabric"

:if ([:len [/ip route find where comment="nixos-config: management default"]] = 0) do={
    /ip route add dst-address=0.0.0.0/0 gateway=192.168.23.1 distance=1 comment="nixos-config: management default"
} else={
    /ip route set [find where comment="nixos-config: management default"] dst-address=0.0.0.0/0 gateway=192.168.23.1 distance=1
}
/ip dns set servers=192.168.23.1

# LAN and fabric presently share this bridge, so routed packets enter and leave
# the same L3 interface. Suppress ICMP redirects: the Linux router must retain
# its explicit fabric route through 192.168.23.27 rather than cache host routes.
/ip settings set send-redirects=no accept-redirects=no secure-redirects=no

# Do not advertise the switch as an IPv6 default router; it has no configured
# upstream IPv6 route and would blackhole clients that accepted such an RA.
:foreach nd in=[/ipv6 nd find where interface=all] do={
    /ipv6 nd set $nd ra-lifetime=none
}

# Enable IPv4/IPv6 unicast route offload. Stateful firewall/NAT remains a CPU
# function on the CRS812, so this switch is the fabric router, not the WAN NAT.
/interface ethernet switch set [find where name="switch1"] l3-hw-offloading=yes qos-hw-offloading=yes

# Switch-wide DSCP classification. During the legacy-flat transition VPP does
# not rewrite its WAN output, so trusted endpoint markings reach this map:
# qBittorrent explicitly emits CS1, AF41 is streaming, EF is interactive, and
# CS7 is router/control. RoCEv2 keeps DSCP 26 in TC3 and CNP DSCP 48 in TC6.
# Profiles are harmless until a matching packet arrives; queue scheduling is
# selected independently per egress port by its tx-manager.
:foreach n in={"nixos-wan-bulk";"nixos-wan-stream";"nixos-wan-interactive";"nixos-wan-control";"nixos-roce";"nixos-cnp"} do={
    /interface ethernet switch qos profile remove [find where name=$n]
}
/interface ethernet switch qos profile add name="nixos-wan-bulk" dscp=8 traffic-class=0
/interface ethernet switch qos profile add name="nixos-wan-stream" dscp=34 traffic-class=4
/interface ethernet switch qos profile add name="nixos-wan-interactive" dscp=46 traffic-class=5
/interface ethernet switch qos profile add name="nixos-wan-control" dscp=56 traffic-class=7
/interface ethernet switch qos profile add name="nixos-roce" dscp=26 traffic-class=3
/interface ethernet switch qos profile add name="nixos-cnp" dscp=48 traffic-class=6

# WAN scheduler.  All ordinary classes share one DWRR group so bulk can yield
# bandwidth without ever being starved; control classes remain strict.  The
# 2026-08-30 provider-policer sweep selected the ASIC's 24.7 Gbit/s step: it
# retained 23.17 Gbit/s of public TCP goodput while reducing concurrent RTT
# from complete probe loss to about 1 ms.  Shape the physical ISP egress so the
# CRS812, rather than the provider policer, owns the queue.
:if ([:len [/interface ethernet switch qos tx-manager find where name="nixos-wan"]] = 0) do={
    /interface ethernet switch qos tx-manager add name="nixos-wan" queue-buffers=auto
}
/interface ethernet switch qos tx-manager queue set [find where tx-manager="nixos-wan" and traffic-class=0] schedule=high-priority-group weight=1 wred=no ecn=no
/interface ethernet switch qos tx-manager queue set [find where tx-manager="nixos-wan" and traffic-class=1] schedule=high-priority-group weight=8 wred=no ecn=no
/interface ethernet switch qos tx-manager queue set [find where tx-manager="nixos-wan" and traffic-class=2] schedule=high-priority-group weight=3 wred=no ecn=no
/interface ethernet switch qos tx-manager queue set [find where tx-manager="nixos-wan" and traffic-class=3] schedule=high-priority-group weight=3 wred=no ecn=no
/interface ethernet switch qos tx-manager queue set [find where tx-manager="nixos-wan" and traffic-class=4] schedule=high-priority-group weight=6 wred=no ecn=no
/interface ethernet switch qos tx-manager queue set [find where tx-manager="nixos-wan" and traffic-class=5] schedule=high-priority-group weight=8 wred=no ecn=no
/interface ethernet switch qos tx-manager queue set [find where tx-manager="nixos-wan" and traffic-class=6] schedule=strict-priority wred=no ecn=no
/interface ethernet switch qos tx-manager queue set [find where tx-manager="nixos-wan" and traffic-class=7] schedule=strict-priority wred=no ecn=no
/interface ethernet switch qos port set [find where name="sfp56-8"] tx-manager="nixos-wan" pfc=disabled
/interface ethernet switch port set [find where name="sfp56-8"] egress-rate=24700M

# Trust L3 markings leaving VPP on the BlueField-facing port. In the current
# flat LAN those include trusted endpoint DSCP; the final VLAN split can make
# VPP the interface-level marking boundary. PFC stays disabled here: Internet
# routing is lossy by design and pause frames must never couple WAN congestion
# back into the fabric.
/interface ethernet switch qos port set [find where name="qsfp56-1-1"] trust-l3=keep pfc=disabled

# Lossless RoCEv2 policy on the fabric ports. PFC remains limited to TC3.
/interface ethernet switch qos tx-manager queue set 1 schedule=high-priority-group weight=1
/interface ethernet switch qos tx-manager queue set 3 schedule=high-priority-group weight=1 ecn=yes wred=no
/interface ethernet switch qos tx-manager queue set 6 schedule=strict-priority wred=no
/interface ethernet switch qos settings set lossless-traffic-class=3 lossless-buffers=auto shared-buffers=auto
/interface ethernet switch qos priority-flow-control remove [find where name="nixos-pfc-tc3"]
/interface ethernet switch qos priority-flow-control add name="nixos-pfc-tc3" traffic-class=3 rx=yes tx=yes
/interface ethernet switch qos port set [find where name="qsfp56-2-1"] trust-l3=keep pfc="nixos-pfc-tc3" egress-rate-queue3=100G
:foreach p in={"qsfp56-dd-2-1";"qsfp56-dd-2-3";"qsfp56-dd-2-5";"qsfp56-dd-2-7"} do={
    /interface ethernet switch qos port set [find where name=$p] trust-l3=keep pfc="nixos-pfc-tc3" egress-rate-queue3=100G
}
# Cage 1's two branches run at 200G, so pause timing needs the higher rate.
# Both branches are RDMA endpoints (strix-2's BlueField-2 and, since
# 2026-08-26, strix-1's ConnectX-7). The retired fabric1
# lanes (-3 and -7) have their PFC cleared so a stale binding from the old
# 4x100G map cannot survive into the new lane layout.
:foreach p in={"qsfp56-dd-1-3";"qsfp56-dd-1-7"} do={
    /interface ethernet switch qos port set [find where name=$p] trust-l3=ignore pfc=disabled
}
:foreach p in={"qsfp56-dd-1-1";"qsfp56-dd-1-5"} do={
    /interface ethernet switch qos port set [find where name=$p] trust-l3=keep pfc="nixos-pfc-tc3" egress-rate-queue3=200G
}

# Rebind the configured high-speed bridge ports after link/QoS changes. RouterOS
# can otherwise leave a trained port in a stale ASIC offload group.
:foreach p in={"qsfp56-2-1";"qsfp56-dd-1-1";"qsfp56-dd-1-5";"qsfp56-dd-2-1";"qsfp56-dd-2-3";"qsfp56-dd-2-5";"qsfp56-dd-2-7"} do={
    :local bp [/interface bridge port find where interface=$p]
    :if ([:len $bp] > 0) do={
        /interface bridge port set $bp hw=no
        :delay 100ms
        /interface bridge port set $bp hw=yes
    }
}

:put "CRS812 declarative fabric configuration applied"
