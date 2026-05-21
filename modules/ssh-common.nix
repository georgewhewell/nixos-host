{config, lib, pkgs, network, ...}:
let
  ip = lib.getExe' pkgs.iproute2 "ip";
  grep = lib.getExe pkgs.gnugrep;
  ssh = lib.getExe pkgs.openssh;
  lanPrefixRegex = builtins.replaceStrings ["."] ["\\."] network.vlans.lan.prefix;
in {
  # This module adds common SSH config to system-level SSH
  programs.ssh.extraConfig = lib.mkBefore ''
    # ProxyCommand for ${network.domains.public} hosts (resolves hostname on jump host, not client)
    Match host *.${network.domains.public} exec "! ${ip} addr 2>/dev/null | ${grep} -q '${lanPrefixRegex}\.'"
      ProxyCommand ${ssh} -W %h:%p grw@${network.domains.public}

    # Direct connection when on local network
    Match host *.${network.domains.public} exec "${ip} addr 2>/dev/null | ${grep} -q '${lanPrefixRegex}\.'"
      ProxyJump none

    # Also handle direct IPs
    Host 78.47.106.113
      ProxyJump none

    # Control master settings
    Host *
      ControlMaster auto
      ControlPath ~/.ssh/control-%r@%h:%p
      ControlPersist 10m
      ServerAliveInterval 60
      ServerAliveCountMax 5
  '';
}
