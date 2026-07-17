# XikeStor SKS8300-8X / LIANGUO LG-SWTGW3C8F-style RTL9303 8x SFP+ switch.
#
# Build:  OPENWRT_ROOT_PASSWORD_HASH='$6$...' nix build --impure .#openwrt-10g-onti
# Flash:  scripts/openwrt-10g-onti-deploy
#
# The root password hash is only for LuCI/web login. SSH is key-only.
{pkgs, openwrt-imagebuilder, rootPasswordHash ? let
  envHash = builtins.getEnv "OPENWRT_ROOT_PASSWORD_HASH";
in
  if envHash == "" then "!" else envHash}:
let
  profiles = openwrt-imagebuilder.lib.profiles {
    inherit pkgs;
    release = "25.12.4";
  };

  sshKeys = import ../../../profiles/ssh-keys.nix;
  authorizedKeys = pkgs.writeText "openwrt-10g-onti-authorized-keys" (
    pkgs.lib.concatStringsSep "\n" (builtins.attrValues sshKeys) + "\n"
  );
  uciDefaults = pkgs.replaceVars ./uci-defaults.sh {
    inherit rootPasswordHash;
  };
in
openwrt-imagebuilder.lib.build (
  profiles.identifyProfile "xikestor_sks8300-8x"
  // {
    extraImageName = "10g-onti";
    packages = [
      "luci"
      "luci-ssl"
      "ethtool"
      "ip-full"
      "prometheus-node-exporter-lua"
      "prometheus-node-exporter-lua-netstat"
      "tcpdump"
    ];
    disabledServices = [
      "dnsmasq"
      "odhcpd"
      "firewall"
    ];
    files = pkgs.runCommand "openwrt-10g-onti-files" {} ''
      mkdir -p $out/etc/dropbear $out/etc/uci-defaults
      install -m0600 ${authorizedKeys} $out/etc/dropbear/authorized_keys
      install -m0755 ${uciDefaults} $out/etc/uci-defaults/99-10g-onti
    '';
  }
)
