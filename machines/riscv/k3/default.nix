{
  config,
  inputs,
  lib,
  mkSecret,
  network,
  pkgs,
  ...
}: let
  sshKeys = import ../../../profiles/ssh-keys.nix;
  self = network.hosts.k3;
  iphoneWan = "iphone0";
  wifiWan = "wlP4p1s0";
  phoneWans = [ iphoneWan wifiWan ];
  backupWan = network.vlans.wanBackup;
  backupTag = "backup${toString backupWan.id}";
  backupPeerIp = network.ipOf "wanBackup" network.hosts.bluefield2.addresses.wanBackup;
  backupPeerCidr = "${backupPeerIp}/32";
  backupBootstrapPeerIp = network.primaryIp network.hosts."bluefield2-vpp-lan";
  backupIngresses = [ backupTag "bond0" ];
  backupAllowedSourceCidrs =
    map
      (name: "${network.primaryIp network.hosts.${name}}/32")
      network.policies.backupWan.allowedSourceHosts
    ++ network.policies.backupWan.additionalSourceCidrs
    ++ [ backupPeerCidr ];
  backupTcpPorts = lib.concatStringsSep "," (map toString network.policies.backupWan.tcpPorts);
  backupUdpPorts = lib.concatStringsSep "," (map toString network.policies.backupWan.udpPorts);
  backupForwardingRules = lib.concatMapStringsSep "\n" (egress:
    lib.concatMapStringsSep "\n" (ingress:
      lib.concatMapStringsSep "\n" (source: ''
        iptables -w -t filter -A nixos-filter-forward -i '${ingress}' -s '${source}' -o '${egress}' -p icmp -j ACCEPT
        iptables -w -t filter -A nixos-filter-forward -i '${ingress}' -s '${source}' -o '${egress}' -p tcp -m multiport --dports '${backupTcpPorts}' -j ACCEPT
        iptables -w -t filter -A nixos-filter-forward -i '${ingress}' -s '${source}' -o '${egress}' -p udp -m multiport --dports '${backupUdpPorts}' -j ACCEPT
      '') backupAllowedSourceCidrs
    ) backupIngresses
  ) phoneWans;
  backupNatRules = lib.concatMapStringsSep "\n" (egress:
    lib.concatMapStringsSep "\n" (source: ''
      iptables -w -t nat -A nixos-nat-post -s '${source}' -o '${egress}' -j MASQUERADE
    '') backupAllowedSourceCidrs
  ) phoneWans;
  backupRpfilterRules = lib.concatMapStringsSep "\n" (ingress:
    lib.concatMapStringsSep "\n" (source: ''
      iptables -w -t mangle -I nixos-fw-rpfilter 1 -i '${ingress}' -s '${source}' -j RETURN
    '') backupAllowedSourceCidrs
  ) backupIngresses;
  backupBootstrapDropRules = lib.concatMapStringsSep "\n" (source: ''
    iptables -w -t filter -A nixos-filter-forward -i 'bond0' -s '${source}' -j DROP
  '') network.policies.backupWan.vppTestReturnCidrs;
  backupSourceRoutingPolicyRules =
    map
      (source: {
        From = source;
        Table = backupWan.id;
        Priority = 10000 + backupWan.id;
        Family = "ipv4";
      })
      backupAllowedSourceCidrs;
  phoneInputRules = lib.concatMapStringsSep "\n" (egress: ''
    iptables -t mangle -I nixos-fw-rpfilter 1 -i ${egress} -j RETURN
    iptables -I nixos-fw 1 -i ${egress} -p udp --sport 67 --dport 68 -j nixos-fw-accept
    iptables -I nixos-fw 2 -i ${egress} -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept
    iptables -I nixos-fw 3 -i ${egress} -j nixos-fw-refuse
    ip6tables -I nixos-fw 1 -i ${egress} -j nixos-fw-refuse
  '') phoneWans;
  phoneForwardDropRules = lib.concatMapStringsSep "\n" (egress: ''
    iptables -w -t filter -A nixos-filter-forward -o '${egress}' -j DROP
  '') phoneWans;
  phoneOutputJumps = lib.concatMapStringsSep "\n" (egress: ''
    while iptables -w -D OUTPUT -o ${egress} -j k3-phone-output 2>/dev/null; do :; done
    iptables -w -I OUTPUT 1 -o ${egress} -j k3-phone-output
    while ip6tables -w -D OUTPUT -o ${egress} -j k3-phone-output-v6 2>/dev/null; do :; done
    ip6tables -w -I OUTPUT 1 -o ${egress} -j k3-phone-output-v6
  '') phoneWans;

  # ---- Rescue tunnel (inbound) -------------------------------------------
  rescueTunnel = network.rescueTunnel;
  rescueNet = network.vlans.rescue;
  rescuePeerCidr = "${rescueTunnel.ax102.wg}/32";
  rescueSubnetCidr = "${rescueNet.prefix}.0/${toString rescueNet.cidr}";
  lanGateway = network.gatewayIp "lan";

  # Arriving through the tunnel is allowed to do exactly what leaving through
  # the phone is allowed to do -- one port policy, not two -- and only into the
  # rescue subnet. Hosts without a rescue address are reached by hopping
  # through k3, not by widening this.
  rescueForwardingRules = ''
    iptables -w -t filter -A nixos-filter-forward -i '${rescueTunnel.interface}' -s '${rescuePeerCidr}' -d '${rescueSubnetCidr}' -o 'bond0' -p icmp -j ACCEPT
    iptables -w -t filter -A nixos-filter-forward -i '${rescueTunnel.interface}' -s '${rescuePeerCidr}' -d '${rescueSubnetCidr}' -o 'bond0' -p tcp -m multiport --dports '${backupTcpPorts}' -j ACCEPT
    iptables -w -t filter -A nixos-filter-forward -i '${rescueTunnel.interface}' -s '${rescuePeerCidr}' -d '${rescueSubnetCidr}' -o 'bond0' -p udp -m multiport --dports '${backupUdpPorts}' -j ACCEPT
    # nixos-filter-forward carries no policy of its own and FORWARD's policy is
    # ACCEPT, so an unmatched packet is permitted unless it is dropped here.
    iptables -w -t filter -A nixos-filter-forward -i '${rescueTunnel.interface}' -j DROP
    # A rescue address does not give a host a route back to 10.102.0.0/24, and
    # in the failure this exists for its default gateway is the casualty. With
    # the source rewritten to k3's own rescue address the reply is an on-link
    # neighbour reply, and no gateway is ever consulted.
    iptables -w -t nat -A nixos-nat-post -s '${rescuePeerCidr}' -d '${rescueSubnetCidr}' -o 'bond0' -j MASQUERADE
  '';

  # The LAN is MTU 9000 and the tunnel path is 1500 less WireGuard overhead, so
  # an unclamped bulk transfer black-holes on PMTU. mangle/FORWARD is not one
  # of the chains the firewall module rebuilds, so delete before appending or
  # every reload adds another copy.
  rescueMssClampRules = ''
    while iptables -w -t mangle -D FORWARD -o '${rescueTunnel.interface}' -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; do :; done
    iptables -w -t mangle -A FORWARD -o '${rescueTunnel.interface}' -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
  '';

  # Private chain, rebuilt idempotently: nixos-fw is flushed on every firewall
  # reload but a chain we create is not.
  rescueInputRules = ''
    iptables -w -N k3-rescue-input 2>/dev/null || true
    iptables -w -F k3-rescue-input
    iptables -w -A k3-rescue-input -s '${rescuePeerCidr}' -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept
    iptables -w -A k3-rescue-input -s '${rescuePeerCidr}' -p icmp -j nixos-fw-accept
    iptables -w -A k3-rescue-input -s '${rescuePeerCidr}' -p tcp --dport 22 -j nixos-fw-accept
    iptables -w -A k3-rescue-input -s '${rescuePeerCidr}' -p tcp --dport 53 -j nixos-fw-accept
    iptables -w -A k3-rescue-input -s '${rescuePeerCidr}' -p udp --dport 53 -j nixos-fw-accept
    iptables -w -A k3-rescue-input -j nixos-fw-refuse
    iptables -w -I nixos-fw 1 -i '${rescueTunnel.interface}' -j k3-rescue-input
    ip6tables -w -I nixos-fw 1 -i '${rescueTunnel.interface}' -j nixos-fw-refuse
  '';

  # Nobody is home for a month, so the two things that must not silently rot
  # are the uplink selection and the tunnel itself. Both are checked here.
  rescueHealthScript = pkgs.writeShellScript "k3-rescue-health" ''
    set -u
    PATH=${lib.makeBinPath [
      pkgs.iproute2
      pkgs.iputils
      pkgs.wireguard-tools
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
      pkgs.systemd
    ]}

    # 1. Is the main path carrying packets? The probe target is pinned via the
    # LAN gateway in 30-bond0, so confirm that pin is still in force before
    # trusting a success -- otherwise the check can be satisfied by the very
    # fallback route it is supposed to decide about.
    main_ok=0
    if ip -4 route get ${rescueTunnel.healthProbeTarget} 2>/dev/null \
       | head -n1 | grep -q " via ${lanGateway} "; then
      for _ in 1 2 3; do
        if ping -c1 -W2 -n ${rescueTunnel.healthProbeTarget} >/dev/null 2>&1; then
          main_ok=1
          break
        fi
      done
    fi

    # 2. Borrow the phone's default into the main table only while the primary
    # is down. Only our own metric-5 route is ever added or removed, so the
    # declarative routes and the policy tables stay untouched.
    phone_default=$(ip -4 route show table ${toString backupWan.id} default 2>/dev/null \
      | grep -v unreachable | head -n1)

    if [ "$main_ok" = 1 ]; then
      ip -4 route del default metric 5 2>/dev/null || true
    elif [ -n "$phone_default" ]; then
      via=$(printf '%s\n' "$phone_default" | awk '{for (i = 1; i < NF; i++) if ($i == "via") print $(i + 1)}')
      dev=$(printf '%s\n' "$phone_default" | awk '{for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1)}')
      if [ -n "$via" ] && [ -n "$dev" ]; then
        ip -4 route replace default via "$via" dev "$dev" metric 5
        echo "main path down; default now via $via dev $dev"
      fi
    else
      echo "main path down and no phone uplink is present: nothing to fail over to" >&2
    fi

    # 3. A tunnel that is up but not handshaking looks identical to a dead one
    # from abroad. WireGuard roams across the failover on its own, so a stale
    # handshake means something worse than a route change: rebuild it.
    latest=$(wg show ${rescueTunnel.interface} latest-handshakes 2>/dev/null | awk '{print $2; exit}')
    if [ -n "''${latest:-}" ]; then
      now=$(date +%s)
      if [ "$latest" = 0 ] || [ $((now - latest)) -gt ${toString rescueTunnel.handshakeStaleSeconds} ]; then
        echo "rescue tunnel handshake stale (last=$latest now=$now); restarting" >&2
        systemctl restart wireguard-${rescueTunnel.interface}.service || true
      fi
    fi
  '';
in {
  imports = [
    inputs.nanokvm.nixosModules.boards.k3.pico-itx.uefi
    inputs.nanokvm.nixosModules.spacemitK3UfsDisko
    ../../../profiles/fleet-core.nix
    ../../../profiles/headless.nix
    ../../../profiles/pray-for-sd-card.nix
    ../../../profiles/wireless.nix
    ../../../profiles/watchdog.nix
    ../../../services/gps.nix
  ];

  sconfig.profile = "server";
  system.stateVersion = "25.05";

  spacemit.k3 = {
    authorizedKeys = builtins.attrValues sshKeys;
    serialConsole.enable = false;
  };

  networking = {
    hostName = "k3";
    useNetworkd = true;
    useDHCP = false;

    # Retain WiFi as a fallback when the USB tether is absent. Neither phone
    # path is a trusted LAN interface: new inbound flows are rejected below.
    wireless = {
      interfaces = lib.mkForce [ wifiWan ];
      networks = lib.mkForce {
        "iPhone (77)" = {
          pskRaw = "ext:iphone-hotspot-password";
          priority = 100;
          hidden = true;
        };
      };
    };

    nat = {
      enable = true;
      enableIPv6 = false;
      # The NixOS NAT module only models one external interface. Keep it null
      # and install the same narrow source/port policy for both phone links.
      externalInterface = null;
      # Avoid the NixOS NAT module's broad internal-interface ACCEPT rules.
      internalInterfaces = [ ];
      internalIPs = [ ];
      extraCommands = ''
        ${backupForwardingRules}
        ${backupNatRules}
        # Rejected transit must never fall through to k3's wired default.
        iptables -w -t filter -A nixos-filter-forward -i '${backupTag}' -j DROP
        ${backupBootstrapDropRules}
        ${phoneForwardDropRules}
        # Appended last, and deliberately after the phone drops above: rescue
        # traffic may reach the rescue subnet, never the metered uplink.
        ${rescueForwardingRules}
        ${rescueMssClampRules}
      '';
    };
    firewall.enable = lib.mkForce true;
  };

  # usbmuxd switches the trusted handset into its multiplexed USB mode; the
  # in-kernel ipheth driver then exposes the actual Ethernet interface.
  services.usbmuxd.enable = true;
  boot.kernelModules = [ "ipheth" ];

  sops.secrets.iphone-hotspot-password = mkSecret "iphone-hotspot-password" { };
  systemd.services.wpa-supplicant-secrets.script = lib.mkAfter ''
    echo "iphone-hotspot-password=$(cat ${config.sops.secrets.iphone-hotspot-password.path})" >> /run/secrets-wpa/wpa_supplicant.conf
  '';

  # ---- Rescue tunnel ------------------------------------------------------
  # k3 dials out to ax102 and holds the session open with a keepalive, because
  # neither the phone hotspot nor a dead ISP link can accept an inbound flow.
  # The endpoint is a literal address on purpose: name resolution is one of the
  # things that breaks in the failures this exists for.
  sops.secrets.wg-rescue-k3-key = mkSecret "wg-rescue-k3-key" { };
  sops.secrets.wg-rescue-psk = mkSecret "wg-rescue-psk" { };

  networking.wireguard.interfaces.${rescueTunnel.interface} = {
    ips = [ "${rescueTunnel.k3.wg}/24" ];
    listenPort = rescueTunnel.listenPort;
    privateKeyFile = config.sops.secrets.wg-rescue-k3-key.path;
    peers = [
      {
        publicKey = rescueTunnel.ax102.publicKey;
        presharedKeyFile = config.sops.secrets.wg-rescue-psk.path;
        allowedIPs = [ "${rescueTunnel.ax102.wg}/32" ];
        endpoint = rescueTunnel.ax102.endpoint;
        # Holds the far side's NAT/conntrack entry open so ax102 can start a
        # session inbound, which is the entire point of the tunnel.
        persistentKeepalive = 25;
      }
    ];
  };

  # The generated unit is a oneshot that runs once at boot. If it loses a race
  # with the network there is nobody here to notice for a month, so let systemd
  # keep trying; the health timer below is the second line of defence.
  systemd.services."wireguard-${rescueTunnel.interface}".serviceConfig = {
    Restart = "on-failure";
    RestartSec = "15s";
  };

  systemd.services.k3-rescue-health = {
    description = "Keep k3's uplink selection and rescue tunnel alive";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = rescueHealthScript;
    };
  };

  systemd.timers.k3-rescue-health = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "30s";
      AccuracySec = "5s";
    };
  };

  # ---- Standby DNS --------------------------------------------------------
  # The whole house is handed exactly one resolver (.31) on a 6h lease, so that
  # host dying takes names down with it. k3 serves the same static records from
  # the same inventory, permanently, as a second answer -- DNS only: a second
  # DHCP server on this segment would be a worse problem than the one it fixes.
  services.dnsmasq = {
    enable = true;
    settings = {
      domain-needed = true;
      bogus-priv = true;
      no-resolv = true;
      no-hosts = true;
      expand-hosts = true;
      domain = network.domains.lan;
      local = "/${network.domains.lan}/";
      bind-dynamic = true;
      # Never the phone links: this resolver is for the LAN and for whoever
      # arrives through the tunnel, not for the internet.
      interface = [ "lo" "bond0" rescueTunnel.interface ];
      except-interface = phoneWans;
      server = rescueTunnel.resolvers;
      # Generated from the same network.nix inventory the router uses.
      address = network.toDnsmasqAddress;
    };
  };

  # k3 must not depend on .31 to resolve a name, or it cannot help when .31 is
  # the casualty. resolvconf detects the local resolver and rewrites
  # /etc/resolv.conf to 127.0.0.1 alone -- listing upstreams here as a fallback
  # would be discarded, so the redundancy lives inside dnsmasq's `server`
  # instead, and dnsmasq is made to come back if it dies.
  services.resolved.enable = lib.mkForce false;
  networking.nameservers = lib.mkForce [ "127.0.0.1" ];
  systemd.services.dnsmasq.serviceConfig = {
    Restart = lib.mkForce "always";
    RestartSec = "5s";
  };

  # Nothing on the rescue path resolves a name -- the tunnel endpoint, the
  # health probe and the upstream resolvers are all literal addresses -- so a
  # dead dnsmasq costs convenience, never reachability.

  # Opens 53 on the trusted LAN only in practice: the phone, BlueField-transit
  # and rescue boundaries all refuse ahead of these rules in nixos-fw, and the
  # rescue chain re-permits 53 for ax102 explicitly.
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  # Put the untrusted WiFi and BlueField transit boundaries ahead of service
  # ports opened elsewhere, and constrain k3-originated phone traffic too.
  networking.firewall.extraCommands = lib.mkAfter ''
    ${phoneInputRules}
    ${backupRpfilterRules}
    ${rescueInputRules}

    iptables -I nixos-fw 4 -i ${backupTag} -s ${backupPeerCidr} -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept
    iptables -I nixos-fw 5 -i ${backupTag} -s ${backupPeerCidr} -p icmp -j nixos-fw-accept
    iptables -I nixos-fw 6 -i ${backupTag} -s ${backupPeerCidr} -p tcp --dport 22 -j nixos-fw-accept
    iptables -I nixos-fw 7 -i ${backupTag} -j nixos-fw-refuse
    ip6tables -I nixos-fw 2 -i ${backupTag} -j nixos-fw-refuse

    # OUTPUT is not one of the chains rebuilt by the NixOS firewall module.
    # Keep one stable jump there and rebuild our private chains idempotently,
    # otherwise every firewall reload accumulates another copy of each rule.
    iptables -w -N k3-phone-output 2>/dev/null || true
    iptables -w -F k3-phone-output
    iptables -w -A k3-phone-output -p udp --sport 68 --dport 67 -j ACCEPT
    iptables -w -A k3-phone-output -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -w -A k3-phone-output -p icmp -j ACCEPT
    iptables -w -A k3-phone-output -p tcp -m multiport --dports ${backupTcpPorts} -j ACCEPT
    iptables -w -A k3-phone-output -p udp -m multiport --dports ${backupUdpPorts} -j ACCEPT
    iptables -w -A k3-phone-output -j DROP
    ip6tables -w -N k3-phone-output-v6 2>/dev/null || true
    ip6tables -w -F k3-phone-output-v6
    ip6tables -w -A k3-phone-output-v6 -j DROP
    ${phoneOutputJumps}
  '';

  system.nixos-init.enable = lib.mkForce false;
  system.etc.overlay.enable = lib.mkForce false;
  services.userborn.enable = lib.mkForce false;
  services.nscd.enable = lib.mkForce false;
  system.nssModules = lib.mkForce [];
  nixpkgs.overlays = [
    inputs.nix-strix-halo.overlays.spacemitK3

    # systemd's BPF framework does not survive cross-compilation to riscv64:
    # the sandboxing objects are built by clang targeting bpf, and in a cross
    # build it is handed none of the target's headers, so
    #   src/bpf/restrict-fs.bpf.c:9:10: fatal error: 'errno.h' file not found
    # kills the whole build. nixpkgs' `withLibBPF` default carves out mips64
    # and riscv32 but not riscv64 (pkgs/os-specific/linux/systemd/default.nix,
    # the `withLibBPF ?` block), so we opt out here.
    #
    # An overlay rather than `systemd.package` so everything that references
    # systemd picks up the same build instead of a second, broken one.
    #
    # Cost: the BPF-backed sandboxing directives (RestrictFilesystems=,
    # SocketBind=, RestrictNetworkInterfaces=) become no-ops on this host.
    (_final: prev: {
      systemd = prev.systemd.override { withLibBPF = false; };
    })
  ];

  # QCN9274 (ath12k), moved here from rock-5b. k3's 6.18.3 vendor kernel
  # already ships the ath12k module, so the card was missing nothing but
  # firmware: with none present the driver never binds and 0000:01:00.0 sits
  # on the bus with no driver at all, while the RTL8852BE (rtw89) carries phy0.
  # This is the same vendor-board variant profiles/router/ap.nix settled on for
  # this card, so its board.bin quirks are already accounted for.
  hardware.firmware = [
    pkgs.qcn9274-fw-1_3_1-00217-mlo-dualmac-primary-vendor-board2-alias
  ];
  hardware.wirelessRegulatoryDatabase = true;

  # GNSS receiver on the board's only probed UART. Of the ten serial nodes the
  # device tree declares, just serial@d4017000 probes into a usable port
  # (ttyS0, XScale type); the rest register as 8250 stubs with no hardware.
  # `spacemit.k3.serialConsole.enable = false` above keeps the kernel console
  # on tty0, so nothing contends for the port.
  # URANUS5 (SW=URANUS5,V5.3.0.0), CASIC/$PCAS command set — confirmed by
  # querying the module, not by guessing: it ignores MTK's $PMTK entirely.
  # Every setting is re-applied at boot rather than saved to the module's
  # flash, so the config in this file is the single source of truth.
  services.gps-receiver = {
    enable = true;
    device = "/dev/ttyS0";
    # Stay at 9600. The 115200 switch works when sent to an idle module by
    # hand, but not from the boot service against a receiver already streaming
    # at 1 Hz — it keeps running at 9600 and gpsd then reads noise. It bought
    # nothing anyway: the headroom was for GLONASS/Galileo, which this module
    # turns out not to support (no $GLGSV or $GAGSV are ever emitted), so
    # GPS+BeiDou fits, if tightly, at ~79% link utilisation.
    powerOnBaudRate = 9600;
    baudRate = 9600;
    initCommands = [
      "PCAS04,7" # GPS + BeiDou + GLONASS (URANUS5 has no Galileo)
      "PCAS11,1" # stationary: fixed install, so constrain velocity to zero
    ];
    # Discipline the clock from the receiver, with network fallback. No PPS on
    # this board (no exposed GPIO), so expect tens of milliseconds rather than
    # stratum-1 accuracy.
    chrony.enable = true;
    exporter = {
      enable = true;
      # The LAN remains trusted; open this explicitly while the phone and
      # BlueField transit boundaries above stay deny-by-default.
      openFirewall = true;
    };
  };

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = ["systemd"];
    openFirewall = true;
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="misc", KERNEL=="tcm", SYMLINK+="tcm_sync_mem"
  '';

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "ondemand";
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  environment.systemPackages = with pkgs; [
    ethtool
    iw
    pciutils
    # fastfetch dropped 2026-08-11: it fails to cross-compile to riscv64 and
    # was blocking the whole system closure for a cosmetic tool.
    btop
    llama-cpp-spacemit
    # For diagnosing the rescue tunnel from the far end of it.
    wireguard-tools
  ] ++ [
    pkgs.pkgsBuildBuild.ghostty.terminfo
  ];

  fileSystems."/boot" = {
    device = lib.mkForce "/dev/disk/by-partlabel/ESP";
    fsType = lib.mkForce "vfat";
    options = lib.mkForce [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  systemd.network.wait-online.enable = lib.mkForce false;
  systemd.network.links."10-iphone-tether" = {
    matchConfig.Driver = "ipheth";
    linkConfig = {
      Name = iphoneWan;
      NamePolicy = "";
    };
  };
  systemd.network.netdevs."10-bond0" = {
    netdevConfig = {
      Kind = "bond";
      Name = "bond0";
      MACAddress = self.mac;
    };
    bondConfig = {
      Mode = "active-backup";
      MIIMonitorSec = "1s";
    };
  };
  systemd.network.netdevs."20-${backupTag}" = {
    netdevConfig = {
      Kind = "vlan";
      Name = backupTag;
    };
    vlanConfig.Id = backupWan.id;
  };
  systemd.network.networks = {
    "20-wifi" = {
      networkConfig = {
        DHCP = lib.mkForce "ipv4";
        IPv6AcceptRA = lib.mkForce false;
        LinkLocalAddressing = "no";
        DNSDefaultRoute = false;
      };
      dhcpV4Config = {
        UseDNS = false;
        UseRoutes = true;
        RouteMetric = lib.mkForce 4096;
        # The handset supplies both its address and gateway; policy selects
        # this table only for explicitly approved backup traffic.
        RouteTable = backupWan.id;
      };
      routingPolicyRules = [
        {
          OutgoingInterface = wifiWan;
          Table = backupWan.id;
          Priority = 9999 + backupWan.id;
          Family = "ipv4";
        }
      ];
      linkConfig.RequiredForOnline = lib.mkForce "no";
    };
    "15-iphone-tether" = {
      matchConfig.Name = iphoneWan;
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
        DNSDefaultRoute = false;
      };
      dhcpV4Config = {
        UseDNS = false;
        UseRoutes = true;
        # Prefer USB when attached; WiFi remains at metric 4096.
        RouteMetric = 2048;
        RouteTable = backupWan.id;
      };
      routingPolicyRules = [
        {
          OutgoingInterface = iphoneWan;
          Table = backupWan.id;
          Priority = 9998 + backupWan.id;
          Family = "ipv4";
        }
      ];
      linkConfig.RequiredForOnline = "no";
    };
    "20-end0-bond-slave" = {
      matchConfig.Name = "end0";
      networkConfig = {
        Bond = "bond0";
        ConfigureWithoutCarrier = true;
      };
      linkConfig.RequiredForOnline = "enslaved";
    };
    "20-enP2p1s0-bond-slave" = {
      matchConfig.Name = "enP2p1s0";
      networkConfig = {
        Bond = "bond0";
        ConfigureWithoutCarrier = true;
      };
      linkConfig.RequiredForOnline = "enslaved";
    };
    "30-bond0" = {
      matchConfig.Name = "bond0";
      vlan = [ backupTag ];
      address = [
        (network.cidrOf "lan" self.addresses.lan)
        # k3 is the rescue subnet's gateway. A second address on the same L2,
        # so it needs no VLAN, no switch change, and nothing else has to be
        # working for it to be reachable from its neighbours.
        (network.cidrOf "rescue" self.addresses.rescue)
      ];
      # Its own resolver, not .31's: see services.dnsmasq above.
      dns = ["127.0.0.1"];
      routes =
        [
          {
            Gateway = network.gatewayIp "lan";
            Metric = 10;
          }
          {
            # Pins the health probe to the main path. Without this pin the
            # failover check would, once it had installed its own fallback
            # default, start succeeding *through* that fallback and flap the
            # route back and forth.
            Destination = "${network.rescueTunnel.healthProbeTarget}/32";
            Gateway = network.gatewayIp "lan";
            Metric = 10;
          }
          {
            # A missing phone DHCP lease must terminate policy lookup here,
            # never fall through to k3's ordinary wired default route.  The
            # handset's DHCP default uses metric 4096 and wins when present.
            Destination = "0.0.0.0/0";
            Type = "unreachable";
            Table = backupWan.id;
            Metric = 32767;
          }
        ]
        ++ map (destination: {
          Destination = destination;
          Gateway = backupBootstrapPeerIp;
          GatewayOnLink = true;
        }) network.policies.backupWan.vppTestReturnCidrs;
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
      };
      routingPolicyRules = backupSourceRoutingPolicyRules;
      linkConfig.RequiredForOnline = "no";
    };
    "40-${backupTag}" = {
      matchConfig.Name = backupTag;
      address = [ (network.cidrOf "wanBackup" self.addresses.wanBackup) ];
      networkConfig = {
        ConfigureWithoutCarrier = true;
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
      linkConfig.RequiredForOnline = "no";
    };
  };

  boot.kernelParams = lib.mkAfter [
    # The QCN9274 in the M.2 slot trains at x2 of an advertised x4, the root
    # port logs CorrErr+/NonFatalErr+, and the card's registers read back as
    # all-ones — which is why ath12k reports "Unknown hardware version ... 0xf"
    # and refuses to probe: 0xf is a non-responding device, not a silicon
    # revision. The same card works on rock-5b, whose config carries a
    # commented-out `pcie_aspm=off` from an earlier fight with this. ASPM link
    # power management is the usual cause of a device that trains low and then
    # stops answering, so take it out of the picture.
    "pcie_aspm=off"
    "noefi"
    "panic_on_oops=1"
    "softlockup_panic=1"
    "hung_task_panic=1"
    "workqueue.panic_on_stall=1"
    "workqueue.watchdog_thresh=60"
    "rcupdate.rcu_cpu_stall_timeout=60"
    "rcupdate.rcu_cpu_stall_suppress=0"
  ];

  boot.kernel.sysctl = {
    "kernel.panic" = lib.mkForce 5;
    "kernel.watchdog" = lib.mkForce 1;
    "kernel.panic_on_oops" = lib.mkForce 1;
    "kernel.softlockup_panic" = lib.mkForce 1;
    "kernel.hung_task_panic" = lib.mkForce 1;
    "kernel.hardlockup_panic" = lib.mkForce 1;
    "kernel.panic_on_rcu_stall" = lib.mkForce 1;
    "kernel.max_rcu_stall_to_panic" = lib.mkForce 1;
    "kernel.watchdog_thresh" = lib.mkForce 30;
    "kernel.hung_task_timeout_secs" = lib.mkForce 120;
    "kernel.panic_print" = lib.mkForce 63;
  };

  systemd.settings.Manager = {
    RuntimeWatchdogSec = lib.mkForce "30s";
    RuntimeWatchdogPreSec = lib.mkForce "off";
    RebootWatchdogSec = lib.mkForce "60s";
    KExecWatchdogSec = lib.mkForce "60s";
  };

  deployment = {
    targetHost = lib.mkDefault (network.ipOf "lan" self.addresses.lan);
    targetUser = "root";
    buildOnTarget = false;
  };
}
