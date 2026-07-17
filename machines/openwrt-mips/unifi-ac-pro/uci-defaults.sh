#!/bin/sh
# First-boot config for the UniFi AC-Pro (OpenWrt) — declarative replacement
# for the manual uci setup. Lays down the VLAN-trunk dumb-AP network and the
# wireless config. Secrets (wifi keys + 802.11r FT key) are NOT baked into the
# image — they ship as placeholders and are injected post-flash from sops
# (see scripts/openwrt-unifiac-inject-secrets). dnsmasq/odhcpd/firewall are
# disabled at build time via disabledServices.

set -e

# --- Network: AR8337 switch trunk on both RJ45s (ports 2,3); CPU = port 0 ---
# Untagged VLAN1 = lan (mgmt 192.168.23.3); tagged VLAN50 = wifi clients.
cat > /etc/config/network <<'EONET'

config interface 'loopback'
	option device 'lo'
	option proto 'static'
	list ipaddr '127.0.0.1/8'

config globals 'globals'
	option ula_prefix 'fde9:c788:4d36::/48'

config switch
	option name 'switch0'
	option reset '1'
	option enable_vlan '1'

config switch_vlan
	option device 'switch0'
	option vlan '1'
	option vid '1'
	option ports '0t 2 3'

config switch_vlan
	option device 'switch0'
	option vlan '2'
	option vid '50'
	option ports '0t 2t 3t'

config device
	option name 'br-lan'
	option type 'bridge'
	list ports 'eth0.1'

config interface 'lan'
	option device 'br-lan'
	option proto 'static'
	list ipaddr '192.168.23.3/24'
	option gateway '192.168.23.1'
	list dns '192.168.23.1'

config device
	option name 'br-wifi'
	option type 'bridge'
	list ports 'eth0.50'

config interface 'wifi'
	option device 'br-wifi'
	option proto 'none'
EONET

# --- Wireless: RFE (WPA3-SAE + 802.11r/k/v) + legacy VM4588425 (WPA2), both
# bands, bridged to VLAN 50. Keys are placeholders, replaced post-flash. ---
cat > /etc/config/wireless <<'EOWL'

config wifi-device 'radio0'
	option type 'mac80211'
	option path 'pci0000:00/0000:00:00.0'
	option band '5g'
	option channel '36'
	option htmode 'VHT80'
	option country 'CH'
	option cell_density '0'

config wifi-iface 'wifi5'
	option device 'radio0'
	option network 'wifi'
	option mode 'ap'
	option ssid 'Radio Free Europe'
	option encryption 'sae'
	option key '__RFE_KEY__'
	option ieee80211w '2'
	option ieee80211r '1'
	option mobility_domain '5246'
	option ft_over_ds '0'
	option ft_psk_generate_local '0'
	option reassociation_deadline '1000'
	option nasid 'unifiacpro5g'
	list r0kh 'ff:ff:ff:ff:ff:ff,*,__FT_KEY__'
	list r1kh '00:00:00:00:00:00,00:00:00:00:00:00,__FT_KEY__'
	option ieee80211k '1'
	option rrm_neighbor_report '1'
	option rrm_beacon_report '1'
	option ieee80211v '1'
	option bss_transition '1'
	option wnm_sleep_mode '1'

config wifi-device 'radio1'
	option type 'mac80211'
	option path 'platform/ahb/18100000.wmac'
	option band '2g'
	option channel '1'
	option htmode 'HT20'
	option country 'CH'
	option cell_density '0'

config wifi-iface 'wifi2'
	option device 'radio1'
	option network 'wifi'
	option mode 'ap'
	option ssid 'Radio Free Europe'
	option encryption 'sae'
	option key '__RFE_KEY__'
	option ieee80211w '2'
	option ieee80211r '1'
	option mobility_domain '5246'
	option ft_over_ds '0'
	option ft_psk_generate_local '0'
	option reassociation_deadline '1000'
	option nasid 'unifiacpro2g'
	list r0kh 'ff:ff:ff:ff:ff:ff,*,__FT_KEY__'
	list r1kh '00:00:00:00:00:00,00:00:00:00:00:00,__FT_KEY__'
	option ieee80211k '1'
	option rrm_neighbor_report '1'
	option rrm_beacon_report '1'
	option ieee80211v '1'
	option bss_transition '1'
	option wnm_sleep_mode '1'

config wifi-iface 'legacy5'
	option device 'radio0'
	option network 'wifi'
	option mode 'ap'
	option ssid 'VM4588425'
	option encryption 'psk2'
	option key '__VM_KEY__'

config wifi-iface 'legacy2'
	option device 'radio1'
	option network 'wifi'
	option mode 'ap'
	option ssid 'VM4588425'
	option encryption 'psk2'
	option key '__VM_KEY__'
EOWL

# --- Hostname ---
uci -q set system.@system[0].hostname='unifi-ac-pro'
uci -q commit system

# --- Prometheus node exporter: bind to the mgmt (lan) IP on :9100 ---
cat > /etc/config/prometheus-node-exporter-lua <<'EOPROM'

config prometheus-node-exporter-lua 'main'
	option listen_interface 'lan'
	option listen_ipv6 '0'
	option listen_port '9100'
EOPROM
/etc/init.d/prometheus-node-exporter-lua enable 2>/dev/null

exit 0
