# CRS804 desired state for the MLX5/BlueField fabric.
# Applied by scripts/mikrotik-crs804-apply-config.

# Preserve the existing management bridge as an Ethernet recovery path. The
# normal LAN management address moves onto the fabric SVI below.
:if ([:len [/interface bridge find where name="bridge-mgmt"]] = 0) do={
    :local oldBridge [/interface bridge find where name="bridge"]
    :if ([:len $oldBridge] > 0) do={
        /interface bridge set $oldBridge name="bridge-mgmt" comment="nixos-config: software Ethernet management bridge"
    } else={
        /interface bridge add name="bridge-mgmt" protocol-mode=rstp vlan-filtering=no mtu=1500 comment="nixos-config: software Ethernet management bridge"
    }
}
/interface bridge set [find where name="bridge-mgmt"] protocol-mode=rstp vlan-filtering=no mtu=1500 comment="nixos-config: software Ethernet management bridge"

# ORDER MATTERS HERE. RouterOS validates a bridge's stored mtu against the
# minimum l2mtu of its CURRENT members on EVERY `set` — not just one that
# names mtu. ether1/ether2 used to be pinned at l2mtu=1600, so with the cages
# dark they were the only members and the bridge sat permanently in the
# "MTU > L2MTU" state with actual-mtu clamped to 1500. Any `/interface bridge
# set` against it then failed with "could not set mtu" and aborted the entire
# import: every port, VLAN and address statement below silently never ran.
# That is what happened on 2026-08-15 (the CRS812 logged the identical error
# on 2026-08-14). Raising the OOB pair to l2mtu=9216 (their max is 9586, and
# their IP mtu stays 1500) lifts the bridge's floor, clears the flag and
# restores actual-mtu=9000 on the fabric SVI. It must happen BEFORE the
# bridge-fabric block below.
/interface ethernet set [find where name="ether1" or name="ether2"] mtu=1500 l2mtu=9216

:if ([:len [/interface bridge find where name="bridge-fabric"]] = 0) do={
    /interface bridge add name="bridge-fabric" protocol-mode=rstp vlan-filtering=no mtu=9000 comment="nixos-config: hardware QSFP fabric bridge"
}
# Filtering is enabled only after all ports and VLAN-table entries exist.
/interface bridge set [find where name="bridge-fabric"] protocol-mode=rstp vlan-filtering=no mtu=9000 auto-mac=no admin-mac=D0:EA:11:D1:9D:85 comment="nixos-config: hardware QSFP fabric bridge"

# Both CPU-connected 10G Ethernet interfaces carry the OOB management
# island (BlueField-2 OOB on ether1, BMC switch on ether2) as ordinary
# LAN access ports in fabric VLAN 25 (2026-07-29: the island lost its
# separate LAN uplink in the re-cabling; it now reaches .23 through the
# fabric bridge like every other untagged port). ether1 additionally reaches
# CRS510 sfp28-7 and is this switch's management lifeline; ether2 carries
# trex's i40e0 second NIC.
:foreach p in={"ether1";"ether2"} do={
    :local bp [/interface bridge port find where interface=$p]
    :if ([:len $bp] = 0) do={
        /interface bridge port add bridge="bridge-fabric" interface=$p hw=yes pvid=25 ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged
    } else={
        /interface bridge port set $bp bridge="bridge-fabric" hw=yes pvid=25 ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged
    }
}

# Physical topology (re-cabled 2026-08-15: this switch becomes the fabric hub
# and the CRS510 drops to a leaf behind it):
#   cage 1: 100G FR optic (Cisco-Innolight TR-FC13T-NCI, LC/1301nm), moved
#           here from CRS510 qsfp28-2-1 -> CRS812 "mikrotik-crs812"
#           qsfp56-2-1. This is the CRS812's ONLY uplink: the fabric gateway
#           192.168.25.1 and strix-1/2/4 all sit behind it.
#   cage 2: 100G DAC -> CRS510 "mikrotik-crs510" qsfp28-1-1, the port trex
#           vacated. Router, fuckup and the OOB island are behind the CRS510.
#   cage 3: 100G DAC -> trex mlxlan0 (moved off CRS510 qsfp28-1-1).
#   cage 4: empty. Freed by this re-cable. Note that bluefield2's
#           QDD-2x200G-CU1M splitter does NOT live here — its DD end is in
#           CRS812 cage 1 (qsfp56-dd-1-*), not on this switch.
#
# The strix hosts are NOT on this switch any more -- they moved to the CRS812
# (qsfp56-dd-2-1/-3/-7, commented "fabric2 strix-N" there) while this switch
# was disconnected. Cages 2 and 3 are no longer breakouts.
#
# Every live cage now carries ONE 100G module on a four-lane primary (-1).
# The forced speed MUST match the installed module: CR4 is a 4x25G QSFP28
# DAC, CR2 is 2x50G -- forcing CR2 onto a QSFP28 cable gives good RX light
# and status no-link, which looks exactly like a crashed peer switch. The
# 2026-08-06 LAN outage was this file's old forced-25G value surviving a cage
# optic swap to 100G FR. Both ends force the same speed and fec91.
#
# First remove every QSFP lane from any old bridge membership. This prevents
# stale primaries from surviving a breakout-mode change. Member lanes remain
# enabled only where their primary needs them for link training.
:for cage from=1 to=4 do={
    :for lane from=1 to=8 do={
        :local p ("qsfp56-dd-" . $cage . "-" . $lane)
        :local bp [/interface bridge port find where interface=$p]
        :if ([:len $bp] > 0) do={
            /interface bridge port remove $bp
        }
        /interface ethernet set [find where name=$p] l2mtu=9216 mtu=9000 disabled=yes
    }
}

# Cage 1: single 100G FR optic to the CRS812. Forced SR4-LR4 and fec91 match
# qsfp56-2-1 at the far end. admit-all because tagged WiFi VLAN 50 transits
# this leg (see the VLAN 50 note below). Lanes 2-4 stay enabled as members of
# the four-lane primary; 5-8 stay disabled with the cage half empty.
/interface ethernet set [find where name="qsfp56-dd-1-1"] disabled=no auto-negotiation=no fec-mode=fec91 speed=100G-baseSR4-LR4
/interface bridge port add bridge="bridge-fabric" interface="qsfp56-dd-1-1" hw=yes pvid=25 ingress-filtering=yes frame-types=admit-all
/interface ethernet switch port set [find where name="qsfp56-dd-1-1"] l3-hw-offloading=no
:foreach lane in={2;3;4} do={
    /interface ethernet set [find where name=("qsfp56-dd-1-" . $lane)] disabled=no
}

# Cage 2: single 100G DAC to the CRS510. Forced CR4/fec91 to match qsfp28-1-1
# there, which the CRS510 already drives at 100G-baseCR4 fec91 (it was trex's
# port). admit-all because this leg carries tagged WiFi VLAN 50 as well as
# the untagged fabric.
/interface ethernet set [find where name="qsfp56-dd-2-1"] disabled=no auto-negotiation=no fec-mode=fec91 speed=100G-baseCR4
/interface bridge port add bridge="bridge-fabric" interface="qsfp56-dd-2-1" hw=yes pvid=25 ingress-filtering=yes frame-types=admit-all
/interface ethernet switch port set [find where name="qsfp56-dd-2-1"] l3-hw-offloading=no
:foreach lane in={2;3;4} do={
    /interface ethernet set [find where name=("qsfp56-dd-2-" . $lane)] disabled=no
}

# Cage 3: single 100G DAC to trex (mlxlan0). The CRS510 drove this same cable
# at 100G-baseCR4 fec91, so trex's ConnectX side needs no change.  Admit tagged
# frames because the VPP proving ground below permits its three isolated VLANs;
# ingress filtering still rejects every VLAN not present in the bridge table.
/interface ethernet set [find where name="qsfp56-dd-3-1"] disabled=no auto-negotiation=no fec-mode=fec91 speed=100G-baseCR4
/interface bridge port add bridge="bridge-fabric" interface="qsfp56-dd-3-1" hw=yes pvid=25 ingress-filtering=yes frame-types=admit-all
/interface ethernet switch port set [find where name="qsfp56-dd-3-1"] l3-hw-offloading=no
:foreach lane in={2;3;4} do={
    /interface ethernet set [find where name=("qsfp56-dd-3-" . $lane)] disabled=no
}

# Cage 4 is deliberately left empty: the strip loop above disabled every lane
# and removed it from the bridge, and nothing below re-enables it.

# Reconcile only the VLAN rows owned by this file.
/interface bridge vlan remove [find where comment="nixos-config: fabric VLAN 25"]
/interface bridge vlan remove [find where comment="nixos-config: router transit VLAN 26"]
/interface bridge vlan add bridge="bridge-fabric" vlan-ids=25 tagged="bridge-fabric" untagged=qsfp56-dd-1-1,qsfp56-dd-2-1,qsfp56-dd-3-1,ether1,ether2 comment="nixos-config: fabric VLAN 25"
/interface bridge vlan remove [find where comment="nixos-config: WiFi VLAN 50"]
/interface bridge vlan remove [find where comment~"WiFi VLAN 50 - added 2026-07-29"]
# VLAN 50 used to be a stub here: it was tagged on the cage-4 CRS510 uplink
# alone, left over from when cage 3 was the router handoff. The re-cable makes
# it load-bearing. The CRS510 and CRS812 were cabled directly to each other,
# so tagged WiFi traffic crossed between them in one hop; that link is gone
# and the CRS812 now reaches the CRS510 through this switch. VLAN 50 must
# therefore be tagged on BOTH uplink cages, or it dies at this hop.
/interface bridge vlan add bridge="bridge-fabric" vlan-ids=50 tagged=qsfp56-dd-1-1,qsfp56-dd-2-1 comment="nixos-config: WiFi VLAN 50"

# Test-only router-on-a-stick path: trex cage 3 to the CRS812 uplink in cage 1.
# These VLANs terminate on BlueField VPP; they are not admitted on any other
# CRS804 port and carry documentation-prefix addresses only.
/interface bridge vlan remove [find where comment="nixos-config: VPP lab VLANs"]
/interface bridge vlan add bridge="bridge-fabric" vlan-ids=3901-3903 tagged=qsfp56-dd-1-1,qsfp56-dd-3-1 comment="nixos-config: VPP lab VLANs"

:if ([:len [/interface vlan find where name="vlan25-fabric"]] = 0) do={
    /interface vlan add name=vlan25-fabric interface="bridge-fabric" vlan-id=25 mtu=9000 comment="nixos-config: fabric SVI"
} else={
    /interface vlan set [find where name="vlan25-fabric"] interface="bridge-fabric" vlan-id=25 mtu=9000 comment="nixos-config: fabric SVI"
}
# 2026-08-15: while this switch was disconnected the CRS812 took over both
# 192.168.25.1 (fabric gateway) and 192.168.23.27 (LAN management). This
# switch renumbers onto .25.2/.23.28 so the two stop contesting the same
# addresses; the CRS812 remains the fabric gateway. The old rows are removed
# by their previous comment keys first, otherwise the reconcile below would
# add a second address and leave the duplicate .1/.27 in place.
/ip address remove [find where comment="nixos-config: fabric gateway"]
:if ([:len [/ip address find where comment="nixos-config: fabric address"]] = 0) do={
    /ip address add address=192.168.25.2/24 interface=vlan25-fabric comment="nixos-config: fabric address"
} else={
    /ip address set [find where comment="nixos-config: fabric address"] address=192.168.25.2/24 interface=vlan25-fabric
}

# The two 25G handoffs replace the old CPU-Ethernet management uplink. The LAN
# management address stays on the hardware-offloaded fabric SVI, now as .28
# under the mikrotik-crs804 DNS name (mikrotik-400g follows the CRS812).
# The factory 192.168.88.1 address remains on bridge-mgmt for recovery.
:if ([:len [/ip address find where comment="nixos-config-lan-mgmt"]] = 0) do={
    /ip address add address=192.168.23.28/24 interface=vlan25-fabric comment="nixos-config-lan-mgmt"
} else={
    /ip address set [find where comment="nixos-config-lan-mgmt"] address=192.168.23.28/24 interface=vlan25-fabric
}
# Fixed fabric members get static neighbors so the L3HW dataplane starts
# deterministically after boot without temporarily disabling offloading.
/ip arp remove [find where address=192.168.25.22 and interface=vlan25-fabric]
/ip arp add address=192.168.25.22 mac-address=B8:CE:F6:F8:D7:AC interface=vlan25-fabric comment="nixos-config: bluefield2 fabric"

# The dedicated router fabric uplink was reassigned to the Strix hosts. Route
# through the management LAN and remove the obsolete VLAN 26 state.
/ip route set [find where dst-address="0.0.0.0/0" and gateway="192.168.23.1"] distance=1 comment="nixos-config: management default"
/ip route remove [find where comment="nixos-config: router transit default"]
/ip address remove [find where comment="nixos-config: router transit"]
/interface vlan remove [find where name="vlan26-router-transit"]

# The factory ND entry (interface=all) defaults to ra-lifetime=30m, which
# advertises the switch as an IPv6 default router on every interface. LAN
# hosts then install it as a v6 default gateway alongside the real router and
# blackhole their internet-bound IPv6 (the switch does not forward v6
# upstream). ra-lifetime=none keeps ND/RA otherwise intact but withdraws the
# default-router claim.
/ipv6 nd set [find where interface=all] ra-lifetime=none

/interface bridge set [find where name="bridge-fabric"] vlan-filtering=yes
/interface ethernet switch set [find where name="switch1"] l3-hw-offloading=yes

# RouterOS 7.23 can leave later high-speed links in a stale ASIC offload group after
# link retraining: the bridge reports learning+forwarding and H, but frames
# reach only the switch CPU. Rebinding each active cage once repairs the group;
# the final and persistent state remains hardware-offloaded.
:foreach p in={"qsfp56-dd-1-1";"qsfp56-dd-2-1";"qsfp56-dd-3-1"} do={
    :local bp [/interface bridge port find where interface=$p]
    /interface bridge port set $bp hw=no
    :delay 100ms
    /interface bridge port set $bp hw=yes
}

# Lossless RoCEv2 policy for RouterOS >= 7.23. DSCP 26 carries RoCE data in
# traffic class 3, while DSCP 48 CNP feedback gets strict-priority class 6.
# ECN is the primary congestion signal. PFC is deliberately limited to TC3 so
# congestion cannot pause management or ordinary fabric traffic.
#
# RouterOS 7.23 automatically builds the DSCP maps from these profiles.
# Remove our ACL before recreating the profile it references; otherwise an
# idempotent re-import cannot remove nixos-roce while the old rule is live.
/interface ethernet switch rule remove [find where comment="nixos-config: unmarked trex RoCEv2"]
/interface ethernet switch qos profile remove [find where name="nixos-roce"]
/interface ethernet switch qos profile remove [find where name="nixos-cnp"]
/interface ethernet switch qos profile add name="nixos-roce" dscp=26 traffic-class=3
/interface ethernet switch qos profile add name="nixos-cnp" dscp=48 traffic-class=6

# Some SPDK/NVMf target QPs still emit DSCP 0. Promote only unmarked IPv4
# RoCEv2 (UDP destination port 4791) in the ASIC. Marked CNP/RoCE continues
# through the normal DSCP map, while ordinary Trex/qBittorrent traffic keeps
# its own class instead of inheriting the old port-wide AF31 workaround.
/interface ethernet switch rule add switch=switch1 ports=qsfp56-dd-3-1 mac-protocol=ip protocol=udp dst-port=4791 dscp=0 new-qos-profile=nixos-roce keep-qos-fields=no comment="nixos-config: unmarked trex RoCEv2"

/interface ethernet switch qos tx-manager queue set 1 schedule=high-priority-group weight=1
/interface ethernet switch qos tx-manager queue set 3 schedule=high-priority-group weight=1 ecn=yes wred=no
/interface ethernet switch qos tx-manager queue set 6 schedule=strict-priority wred=no
/interface ethernet switch qos settings set lossless-traffic-class=3 lossless-buffers=auto shared-buffers=auto

/interface ethernet switch qos priority-flow-control remove [find where name="nixos-pfc-tc3"]
/interface ethernet switch qos priority-flow-control add name="nixos-pfc-tc3" traffic-class=3 rx=yes tx=yes

# Clear PFC off every lane first, the same way bridge membership is stripped
# above. Without this, lanes that were primaries under an older cage map keep
# their PFC binding forever — the 2026-08-15 rewrite left it stranded on
# qsfp56-dd-3-7 and qsfp56-dd-4-1 — and a future re-cable would silently
# inherit lossless settings that this file never granted.
:for cage from=1 to=4 do={
    :for lane from=1 to=8 do={
        /interface ethernet switch qos port set [find where name=("qsfp56-dd-" . $cage . "-" . $lane)] trust-l3=ignore pfc=disabled
    }
}

# PFC requires an explicit queue rate to calculate pause timing. These rates
# mirror each cage's endpoint ceiling but do not select the physical link mode.
# Cages 1-3 are single 100G links after the 2026-08-15 re-cable: cage 1 to the
# CRS812, cage 2 to the CRS510, cage 3 to trex (an RDMA endpoint).
:foreach p in={"qsfp56-dd-1-1";"qsfp56-dd-2-1"} do={
    /interface ethernet switch qos port set [find where name=$p] profile=default trust-l3=keep pfc="nixos-pfc-tc3" egress-rate-queue3=100G
}

# Trust Trex's L3 marking. The UDP/4791 ACL above retains the old workaround
# for unmarked RoCE without rewriting every ordinary packet to AF31. That
# broad rewrite put qBittorrent and a 23.7 Gbit/s Internet load into lossless
# TC3; after narrowing it, CS1 uses TC0, EF uses TC5, and UDP/4791 still uses
# TC3. PFC remains confined to the actual RoCE class.
/interface ethernet switch qos port set [find where name="qsfp56-dd-3-1"] profile=default trust-l3=keep pfc="nixos-pfc-tc3" egress-rate-queue3=100G
# The 98DX7335 always enables QoS offload on current RouterOS, but retain the
# explicit setting so the desired state remains clear across upgrades.
/interface ethernet switch set [find where name="switch1"] qos-hw-offloading=yes

:put "CRS804 declarative fabric configuration applied"
