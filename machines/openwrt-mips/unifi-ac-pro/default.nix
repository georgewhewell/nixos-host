# UniFi AC-Pro (Gen2 / U7PG2, QCA9563 + AR8337, ath79/generic, mips_24kc).
#
# A declarative OpenWrt "machine": a reproducible firmware image built with
# nix-openwrt-imagebuilder. It runs as a dumb AP on VLAN 50 with WPA3-SAE +
# 802.11r/k/v fast roaming alongside rock-5b, plus a WPA2 legacy SSID.
#
# Secrets (wifi keys, 802.11r FT key) are NOT baked into the image — the image
# ships placeholders, injected post-flash from sops via
# scripts/openwrt-unifiac-inject-secrets.
#
# Build:   nix build .#openwrt-unifiac-pro
# Flash:   cat result/*-sysupgrade.bin | ssh root@<ap> 'cat >/tmp/x'
#          ssh root@<ap> 'sysupgrade -n /tmp/x'
# Secrets: scripts/openwrt-unifiac-inject-secrets root@<ap>   (run on fuckup)
{ pkgs, openwrt-imagebuilder }:
let
  profiles = openwrt-imagebuilder.lib.profiles {
    inherit pkgs;
    release = "25.12.4";
  };
in
openwrt-imagebuilder.lib.build (
  profiles.identifyProfile "ubnt_unifiac-pro"
  // {
    # Swap stock wpad-basic (no WNM/802.11v) for full wpad-mbedtls, add LuCI,
    # plus the prometheus node exporter (:9100) with wifi/station collectors
    # so the fleet's Grafana/VictoriaMetrics can scrape per-AP wifi metrics.
    packages = [
      "-wpad-basic-mbedtls"
      "wpad-mbedtls"
      "luci"
      "luci-ssl"
      "prometheus-node-exporter-lua"
      "prometheus-node-exporter-lua-wifi"
      "prometheus-node-exporter-lua-wifi_stations"
      "prometheus-node-exporter-lua-netstat"
    ];
    # Dumb AP: no DHCP server, no RA, no firewall.
    disabledServices = [ "dnsmasq" "odhcpd" "firewall" ];
    # Baked first-boot config (network VLAN trunk + wireless).
    files = pkgs.runCommand "unifiac-pro-files" { } ''
      mkdir -p $out/etc/uci-defaults
      install -m0755 ${./uci-defaults.sh} $out/etc/uci-defaults/99-unifiac
    '';
  }
)
