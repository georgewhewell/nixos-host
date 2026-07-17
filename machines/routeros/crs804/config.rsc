# CRS804 desired state for the MLX5/BlueField fabric.
# Applied by scripts/mikrotik-400g-apply-config.

# Preserve the existing management bridge object so its IP addresses never
# leave a running interface during migration.
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
# management/recovery LAN. hw=yes is harmless here and permits fast-path
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

# All four cages are members of the flat fabric (VLAN 25). Set L2MTU before
# MTU: RouterOS otherwise rejects mtu=9000 against the factory l2mtu=1584.
:for cage from=1 to=4 do={
    :for lane from=1 to=8 do={
        :local p ("qsfp56-dd-" . $cage . "-" . $lane)
        /interface ethernet set [find where name=$p] l2mtu=9216
        /interface ethernet set [find where name=$p] mtu=9000

        :local bp [/interface bridge port find where interface=$p]
        :if ([:len $bp] = 0) do={
            /interface bridge port add bridge="bridge-fabric" interface=$p hw=yes pvid=25 ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged
        } else={
            /interface bridge port set $bp bridge="bridge-fabric" hw=yes pvid=25 ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged
        }

        # The 98DX7335/RouterOS 7.23 combination installs duplicate external
        # FDB entries (internal VID 4098) when L3HW is enabled on these access
        # ports, breaking ordinary cage-to-cage traffic. L2 bridge offload
        # remains enabled through hw=yes and is the fast path used by RoCE.
        /interface ethernet switch port set [find where name=$p] l3-hw-offloading=no
    }
}

# Cage 1 is a QSFP-DD 400G -> 2x QSFP56 200G breakout. Lanes 1-4 lead to
# strix-1's ConnectX-5 (100G ceiling); lanes 5-8 lead to BlueField-2 at 200G.
# CRS804's 200G breakout mode requires a forced speed on that four-lane group.
# The strix-1 branch is already known-good with autonegotiation at 100G, while
# the BlueField branch is forced to 200G CR4 at both ends.
/interface ethernet set [find where name="qsfp56-dd-1-1"] auto-negotiation=yes fec-mode=auto advertise=10G-baseCR,25G-baseCR,40G-baseCR4,50G-baseCR,50G-baseCR2,100G-baseCR2,100G-baseCR4
/interface ethernet set [find where name="qsfp56-dd-1-5"] auto-negotiation=no fec-mode=auto speed=200G-baseCR4

# Cages 2-4 remain single 100G ConnectX-5 links. Advertise every common
# copper mode through 100G; these are capability ceilings, not forced modes.
:foreach p in={"qsfp56-dd-2-1";"qsfp56-dd-3-1";"qsfp56-dd-4-1"} do={
    /interface ethernet set [find where name=$p] auto-negotiation=yes fec-mode=auto advertise=10G-baseCR,25G-baseCR,40G-baseCR4,50G-baseCR,50G-baseCR2,100G-baseCR2,100G-baseCR4
}

# Reconcile only the VLAN rows owned by this file.
/interface bridge vlan remove [find where comment="nixos-config: fabric VLAN 25"]
/interface bridge vlan remove [find where comment="nixos-config: router transit VLAN 26"]
/interface bridge vlan add bridge="bridge-fabric" vlan-ids=25 tagged="bridge-fabric" untagged=qsfp56-dd-1-1,qsfp56-dd-1-2,qsfp56-dd-1-3,qsfp56-dd-1-4,qsfp56-dd-1-5,qsfp56-dd-1-6,qsfp56-dd-1-7,qsfp56-dd-1-8,qsfp56-dd-2-1,qsfp56-dd-2-2,qsfp56-dd-2-3,qsfp56-dd-2-4,qsfp56-dd-2-5,qsfp56-dd-2-6,qsfp56-dd-2-7,qsfp56-dd-2-8,qsfp56-dd-3-1,qsfp56-dd-3-2,qsfp56-dd-3-3,qsfp56-dd-3-4,qsfp56-dd-3-5,qsfp56-dd-3-6,qsfp56-dd-3-7,qsfp56-dd-3-8,qsfp56-dd-4-1,qsfp56-dd-4-2,qsfp56-dd-4-3,qsfp56-dd-4-4,qsfp56-dd-4-5,qsfp56-dd-4-6,qsfp56-dd-4-7,qsfp56-dd-4-8 comment="nixos-config: fabric VLAN 25"

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
:foreach p in={"qsfp56-dd-1-1";"qsfp56-dd-1-5";"qsfp56-dd-2-1";"qsfp56-dd-3-1";"qsfp56-dd-4-1"} do={
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
:foreach p in={"qsfp56-dd-1-1";"qsfp56-dd-2-1";"qsfp56-dd-3-1";"qsfp56-dd-4-1"} do={
    /interface ethernet switch qos port set [find where name=$p] trust-l3=keep pfc="nixos-pfc-tc3" egress-rate-queue3=100G
}
/interface ethernet switch qos port set [find where name="qsfp56-dd-1-5"] trust-l3=keep pfc="nixos-pfc-tc3" egress-rate-queue3=200G

# The 98DX7335 always enables QoS offload on current RouterOS, but retain the
# explicit setting so the desired state remains clear across upgrades.
/interface ethernet switch set [find where name="switch1"] qos-hw-offloading=yes

:put "CRS804 declarative fabric configuration applied"
