# CRS804 desired state for the MLX5/BlueField fabric.
# Applied by scripts/mikrotik-400g-apply-config.

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

:if ([:len [/interface bridge find where name="bridge-fabric"]] = 0) do={
    /interface bridge add name="bridge-fabric" protocol-mode=rstp vlan-filtering=no mtu=9000 comment="nixos-config: hardware QSFP fabric bridge"
}
# Filtering is enabled only after all ports and VLAN-table entries exist.
/interface bridge set [find where name="bridge-fabric"] protocol-mode=rstp vlan-filtering=no mtu=9000 auto-mac=no admin-mac=D0:EA:11:D1:9D:85 comment="nixos-config: hardware QSFP fabric bridge"

# Both CPU-connected 10G Ethernet interfaces remain a software-switched
# recovery LAN. hw=yes is harmless here and permits fast-path
# behavior if RouterOS gains hardware support for these ports later.
:foreach p in={"ether1";"ether2"} do={
    /interface ethernet set [find where name=$p] mtu=1500 l2mtu=1600
    :local bp [/interface bridge port find where interface=$p]
    :if ([:len $bp] = 0) do={
        /interface bridge port add bridge="bridge-mgmt" interface=$p hw=yes pvid=1 ingress-filtering=yes frame-types=admit-all
    } else={
        /interface bridge port set $bp bridge="bridge-mgmt" hw=yes pvid=1 ingress-filtering=yes frame-types=admit-all
    }
}

# Physical topology:
#   cage 1: 400G -> 2x200G, primary interfaces -1 and -5 (four lanes each)
#   cage 2: 400G -> 4x100G to strix-1..4, primaries -1/-3/-5/-7
#            (two lanes each)
#   cage 3: QSFP-to-SFP28 adapter, 25G untagged router LAN uplink
#   cage 4: QSFP-to-SFP28 adapter, 25G untagged uplink to the CRS504/Trex
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

# Cage 1: two 200G CR4 access links.
:foreach p in={"qsfp56-dd-1-1";"qsfp56-dd-1-5"} do={
    /interface ethernet set [find where name=$p] disabled=no auto-negotiation=no fec-mode=auto speed=200G-baseCR4
    /interface bridge port add bridge="bridge-fabric" interface=$p hw=yes pvid=25 ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged
    /interface ethernet switch port set [find where name=$p] l3-hw-offloading=no
}
:foreach lane in={2;3;4;6;7;8} do={
    :local p ("qsfp56-dd-1-" . $lane)
    /interface ethernet set [find where name=$p] disabled=no
}

# Cage 2: four independent 100G CR2 access links, in cable-leg order to
# strix-1, strix-2, strix-3, and strix-4.
:foreach p in={"qsfp56-dd-2-1";"qsfp56-dd-2-3";"qsfp56-dd-2-5";"qsfp56-dd-2-7"} do={
    /interface ethernet set [find where name=$p] disabled=no auto-negotiation=no fec-mode=auto speed=100G-baseCR2
    /interface bridge port add bridge="bridge-fabric" interface=$p hw=yes pvid=25 ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged
    /interface ethernet switch port set [find where name=$p] l3-hw-offloading=no
}
:foreach lane in={2;4;6;8} do={
    :local p ("qsfp56-dd-2-" . $lane)
    /interface ethernet set [find where name=$p] disabled=no
}

# Cages 3 and 4: ordinary 25G optical access ports in fabric VLAN 25. The
# router and CRS504 continue to see untagged Ethernet. Both known peers use
# forced 25G with RS-FEC; matching that here avoids the failed autonegotiation
# seen when the cage-4 peer does not advertise.
:foreach p in={"qsfp56-dd-3-1";"qsfp56-dd-4-1"} do={
    /interface ethernet set [find where name=$p] disabled=no auto-negotiation=no fec-mode=fec91 speed=25G-baseSR-LR
    /interface bridge port add bridge="bridge-fabric" interface=$p hw=yes pvid=25 ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged
    /interface ethernet switch port set [find where name=$p] l3-hw-offloading=no
}

# Reconcile only the VLAN rows owned by this file.
/interface bridge vlan remove [find where comment="nixos-config: fabric VLAN 25"]
/interface bridge vlan remove [find where comment="nixos-config: router transit VLAN 26"]
/interface bridge vlan add bridge="bridge-fabric" vlan-ids=25 tagged="bridge-fabric" untagged=qsfp56-dd-1-1,qsfp56-dd-1-5,qsfp56-dd-2-1,qsfp56-dd-2-3,qsfp56-dd-2-5,qsfp56-dd-2-7,qsfp56-dd-3-1,qsfp56-dd-4-1 comment="nixos-config: fabric VLAN 25"

:if ([:len [/interface vlan find where name="vlan25-fabric"]] = 0) do={
    /interface vlan add name=vlan25-fabric interface="bridge-fabric" vlan-id=25 mtu=9000 comment="nixos-config: fabric SVI"
} else={
    /interface vlan set [find where name="vlan25-fabric"] interface="bridge-fabric" vlan-id=25 mtu=9000 comment="nixos-config: fabric SVI"
}
:if ([:len [/ip address find where comment="nixos-config: fabric gateway"]] = 0) do={
    /ip address add address=192.168.25.1/24 interface=vlan25-fabric comment="nixos-config: fabric gateway"
} else={
    /ip address set [find where comment="nixos-config: fabric gateway"] address=192.168.25.1/24 interface=vlan25-fabric
}

# The two 25G handoffs replace the old CPU-Ethernet management uplink. Keep the
# established LAN address and DNS name on the hardware-offloaded fabric SVI.
# The factory 192.168.88.1 address remains on bridge-mgmt for recovery.
:if ([:len [/ip address find where comment="nixos-config-lan-mgmt"]] = 0) do={
    /ip address add address=192.168.23.27/24 interface=vlan25-fabric comment="nixos-config-lan-mgmt"
} else={
    /ip address set [find where comment="nixos-config-lan-mgmt"] address=192.168.23.27/24 interface=vlan25-fabric
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
:foreach p in={"qsfp56-dd-1-1";"qsfp56-dd-1-5";"qsfp56-dd-2-1";"qsfp56-dd-2-3";"qsfp56-dd-2-5";"qsfp56-dd-2-7";"qsfp56-dd-3-1";"qsfp56-dd-4-1"} do={
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
/interface ethernet switch qos profile remove [find where name="nixos-roce"]
/interface ethernet switch qos profile remove [find where name="nixos-cnp"]
/interface ethernet switch qos profile add name="nixos-roce" dscp=26 traffic-class=3
/interface ethernet switch qos profile add name="nixos-cnp" dscp=48 traffic-class=6

/interface ethernet switch qos tx-manager queue set 1 schedule=high-priority-group weight=1
/interface ethernet switch qos tx-manager queue set 3 schedule=high-priority-group weight=1 ecn=yes wred=no
/interface ethernet switch qos tx-manager queue set 6 schedule=strict-priority wred=no
/interface ethernet switch qos settings set lossless-traffic-class=3 lossless-buffers=auto shared-buffers=auto

/interface ethernet switch qos priority-flow-control remove [find where name="nixos-pfc-tc3"]
/interface ethernet switch qos priority-flow-control add name="nixos-pfc-tc3" traffic-class=3 rx=yes tx=yes

# PFC requires an explicit queue rate to calculate pause timing.  These rates
# mirror each cage's endpoint ceiling but do not select the physical link mode.
:foreach p in={"qsfp56-dd-2-1";"qsfp56-dd-2-3";"qsfp56-dd-2-5";"qsfp56-dd-2-7"} do={
    /interface ethernet switch qos port set [find where name=$p] trust-l3=keep pfc="nixos-pfc-tc3" egress-rate-queue3=100G
}
:foreach p in={"qsfp56-dd-1-1";"qsfp56-dd-1-5"} do={
    /interface ethernet switch qos port set [find where name=$p] trust-l3=keep pfc="nixos-pfc-tc3" egress-rate-queue3=200G
}
# Cage 3 carries ordinary routed LAN traffic; explicitly clear the stale PFC
# profile left by its former 100G fabric role. Cage 4 carries Trex/RDMA traffic
# and therefore participates in the lossless TC3 policy at its 25G line rate.
/interface ethernet switch qos port set [find where name="qsfp56-dd-3-1"] trust-l3=keep pfc=disabled egress-rate-queue3=25G
/interface ethernet switch qos port set [find where name="qsfp56-dd-4-1"] trust-l3=keep pfc="nixos-pfc-tc3" egress-rate-queue3=25G
# The 98DX7335 always enables QoS offload on current RouterOS, but retain the
# explicit setting so the desired state remains clear across upgrades.
/interface ethernet switch set [find where name="switch1"] qos-hw-offloading=yes

:put "CRS804 declarative fabric configuration applied"
