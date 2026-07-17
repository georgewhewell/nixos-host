{config, lib, pkgs, network, ...}:
let
  ip = lib.getExe' pkgs.iproute2 "ip";
  grep = lib.getExe pkgs.gnugrep;
  ssh = lib.getExe pkgs.openssh;
  lanPrefixRegex = builtins.replaceStrings ["."] ["\\."] network.vlans.lan.prefix;
  strixNames = map (index: "strix-${toString index}") [ 1 2 3 4 ];
  strixSshHosts = lib.concatStringsSep " " (
    strixNames
    ++ map network.fqdn strixNames
    ++ map (name: network.primaryIp network.hosts.${name}) strixNames
  );
in {
  # This module adds common SSH config to system-level SSH
  programs.ssh.extraConfig = lib.mkBefore ''
    # Diskless Strix hosts intentionally generate fresh host keys in tmpfs on
    # every boot. Scope the exception to their inventory names and addresses;
    # host-key verification remains enabled everywhere else. This system-level
    # rule also covers root, Nix builders, Hydra and other OpenSSH callers.
    Host ${strixSshHosts}
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
      UpdateHostKeys no
      LogLevel ERROR

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
