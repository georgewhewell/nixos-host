#!/bin/sh
# First-boot config for the XikeStor SKS8300-8X / 10g-onti OpenWrt image.

set -e

root_hash='@rootPasswordHash@'

cat > /etc/config/network <<'EONET'

config interface 'loopback'
	option device 'lo'
	option proto 'static'
	list ipaddr '127.0.0.1/8'

config globals 'globals'
	option ula_prefix 'fdde:ad::/48'

config device 'switch'
	option name 'switch'
	option type 'bridge'
	option macaddr 'd0:aa:5f:01:45:a8'

config bridge-vlan 'lan_vlan'
	option device 'switch'
	option vlan '1'
	option ports 'lan1 lan2 lan3 lan4 lan5 lan6 lan7 lan8'

config device
	option name 'switch.1'
	option macaddr 'd0:aa:5f:01:45:a8'

config interface 'lan'
	option device 'switch.1'
	option proto 'static'
	list ipaddr '192.168.23.20/24'
	list ip6addr 'fdde:ad::20/64'
	option gateway '192.168.23.1'
	list dns '192.168.23.1'
	list dns 'fdde:ad::1'
	option delegate '0'
EONET

# Management IPv6 is ULA-only. Do not accept LAN router advertisements, because
# that would give the switch a public ISP-prefix address.
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-10g-onti-ipv6.conf <<'EOSYS'
net.ipv6.conf.all.accept_ra=0
net.ipv6.conf.default.accept_ra=0
EOSYS
sysctl -q -p /etc/sysctl.d/99-10g-onti-ipv6.conf || true

uci -q set system.@system[0].hostname='10g-onti'
uci -q commit system

# SSH remains key-only. The root password hash is for LuCI/rpcd login.
uci -q set dropbear.@dropbear[0].PasswordAuth='off'
uci -q set dropbear.@dropbear[0].RootPasswordAuth='off'
uci -q commit dropbear

if [ -n "$root_hash" ]; then
	awk -v hash="$root_hash" 'BEGIN { FS = OFS = ":" } $1 == "root" { $2 = hash } { print }' /etc/shadow > /tmp/shadow
	cat /tmp/shadow > /etc/shadow
	rm -f /tmp/shadow
fi

/etc/init.d/uhttpd enable 2>/dev/null || true
/etc/init.d/rpcd enable 2>/dev/null || true

cat > /etc/config/prometheus-node-exporter-lua <<'EOPROM'

config prometheus-node-exporter-lua 'main'
	option listen_interface 'lan'
	option listen_ipv6 '0'
	option listen_port '9100'
EOPROM
/etc/init.d/prometheus-node-exporter-lua enable 2>/dev/null || true

exit 0
