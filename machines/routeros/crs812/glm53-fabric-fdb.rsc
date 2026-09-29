# Apply separately to the live CRS812; no port, VLAN, PFC or link changes.
# Verified 2026-09-29: dynamic learning flooded unicast RDMA to other ports.
# Pin only the measured fabric destinations. Revalidate after recabling.
# The two host pairs currently share an external switch port; do not use
# the stale per-host cable comments as the forwarding map.
# Rollback: /interface bridge host remove [find where comment~"^glm53:"]

:if ([:len [/interface bridge host find where comment="glm53: strix-1 fabric unicast"]] = 0) do={
    /interface bridge host add bridge=bridge interface=qsfp56-dd-2-1 mac-address=1C:34:DA:61:12:B5 vid=1 comment="glm53: strix-1 fabric unicast"
} else={
    /interface bridge host set [find where comment="glm53: strix-1 fabric unicast"] bridge=bridge interface=qsfp56-dd-2-1 mac-address=1C:34:DA:61:12:B5 vid=1
}
:if ([:len [/interface bridge host find where comment="glm53: strix-2 fabric unicast"]] = 0) do={
    /interface bridge host add bridge=bridge interface=qsfp56-dd-2-1 mac-address=1C:34:DA:61:12:B1 vid=1 comment="glm53: strix-2 fabric unicast"
} else={
    /interface bridge host set [find where comment="glm53: strix-2 fabric unicast"] bridge=bridge interface=qsfp56-dd-2-1 mac-address=1C:34:DA:61:12:B1 vid=1
}
:if ([:len [/interface bridge host find where comment="glm53: strix-3 fabric unicast"]] = 0) do={
    /interface bridge host add bridge=bridge interface=qsfp56-dd-2-5 mac-address=B8:59:9F:54:DB:E9 vid=1 comment="glm53: strix-3 fabric unicast"
} else={
    /interface bridge host set [find where comment="glm53: strix-3 fabric unicast"] bridge=bridge interface=qsfp56-dd-2-5 mac-address=B8:59:9F:54:DB:E9 vid=1
}
:if ([:len [/interface bridge host find where comment="glm53: strix-4 fabric unicast"]] = 0) do={
    /interface bridge host add bridge=bridge interface=qsfp56-dd-2-5 mac-address=B8:59:9F:54:DB:E5 vid=1 comment="glm53: strix-4 fabric unicast"
} else={
    /interface bridge host set [find where comment="glm53: strix-4 fabric unicast"] bridge=bridge interface=qsfp56-dd-2-5 mac-address=B8:59:9F:54:DB:E5 vid=1
}
:if ([:len [/interface bridge host find where comment="glm53: trex fabric unicast"]] = 0) do={
    /interface bridge host add bridge=bridge interface=qsfp56-dd-1-1 mac-address=50:6B:4B:0D:24:86 vid=1 comment="glm53: trex fabric unicast"
} else={
    /interface bridge host set [find where comment="glm53: trex fabric unicast"] bridge=bridge interface=qsfp56-dd-1-1 mac-address=50:6B:4B:0D:24:86 vid=1
}
