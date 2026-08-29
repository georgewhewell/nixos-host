{
  lib,
  network,
}: let
  production = network.routing.production;
  platform = import ./vpp-platform.nix {inherit network;};
  parent = platform.dataName;
  primaryWan = production.wans.primary;
  primaryWanInterface = "${parent}.${toString primaryWan.vlanId}";
  backupWan = production.wans.backup;
  backupWanInterface = "${parent}.${toString backupWan.vlanId}";
  prefixGroup = primaryWan.ipv6.prefixGroup;

  zone = name: let
    declaration = production.zones.${name};
    vlan = network.vlans.${declaration.network};
  in
    declaration
    // {
      inherit name;
      inherit vlan;
      mtu = declaration.mtu or (vlan.mtu or 1500);
    };
  zones = map zone production.zoneOrder;
  controlPlane = production.transition.controlPlane;
  lanZone = zone "lan";
  interfaceName = z: "${parent}.${toString z.vlanId}";
  ipv4Network = z: "${z.vlan.prefix}.0/${toString z.vlan.cidr}";
  ipv4Gateway = z: "${network.gatewayIp z.network}/${toString z.vlan.cidr}";
  ipv4GatewayHost = z: network.gatewayIp z.network;
  ulaPrefix = z: "fdde:ad:${z.ipv6SubnetId}";
  ulaNetwork = z: "${ulaPrefix z}::/64";
  ulaGateway = z: "${ulaPrefix z}::1/64";
  # VPP overlays the delegated prefix bits onto this suffix.  Keeping the
  # subnet ID in hextet four works for both the observed /48 and hinted /56.
  delegatedSuffix = z: "::${z.ipv6SubnetId}:0:0:0:1/64";

  controlPlaneRouteCommands = lib.concatStringsSep "\n" (
    map
    (prefix: "ip route add ${prefix} via ${controlPlane.targetIp} ${interfaceName lanZone}")
    controlPlane.routedIpv4
    ++ map
    (prefix: "ip route add ${prefix} via ${controlPlane.targetIpv6} ${interfaceName lanZone}")
    controlPlane.routedIpv6
  );

  workerCount = builtins.length platform.dataplane.workerCores;
  useRdma = platform.dataplane.driver == "rdma";
  zoneInterfaceCommands = lib.concatStringsSep "\n" (
    map (z: "create sub-interfaces ${parent} ${toString z.vlanId}") zones
    ++ map (z: "set interface mtu packet ${toString z.mtu} ${interfaceName z}") zones
    ++ map (z: "set interface state ${interfaceName z} up") zones
    ++ map (z: "set interface ip address ${interfaceName z} ${ipv4Gateway z}") zones
    ++ map (z: "set interface ip address ${interfaceName z} ${ulaGateway z}") zones
    ++ map (z: "set ip6 address ${interfaceName z} prefix group ${prefixGroup} ${delegatedSuffix z}") zones
    # VPP's CLI takes the maximum interval first, then the minimum.
    ++ map (z: "ip6 nd ${interfaceName z} ra-interval 60 30 ra-lifetime 180") zones
    ++ map (z: "ip6 nd ${interfaceName z} prefix ${ulaNetwork z} 86400 14400") zones
  );

  portForwardHosts = import ../../../profiles/router/port-forwards.nix network;
  selectedPublicationGroups =
    lib.filterAttrs
    (name: _: builtins.elem name production.nat44.publicationGroups)
    portForwardHosts;
  expandProtocols = forward:
    if forward.proto == "both"
    then ["tcp" "udp"]
    else [forward.proto];
  publications = lib.concatLists (lib.mapAttrsToList
    (group: host:
      lib.concatMap
      (forward:
        map
        (protocol: {
          inherit group protocol;
          target = host.ip;
          localPort = forward.dstPort or forward.port;
          externalPort = forward.port;
        })
        (expandProtocols forward))
      host.forwards)
    selectedPublicationGroups);
  zoneForAddress = address:
    lib.findFirst
    (z: lib.hasPrefix "${z.vlan.prefix}." address)
    (throw "production publication target ${address} is outside every routed zone")
    zones;

  natCommands = lib.concatStringsSep "\n" (
    [
      "set nat frame-queue-nelts ${toString production.nat44.frameQueueLength}"
      "nat44 plugin enable sessions ${toString production.nat44.sessions}"
      "nat mss-clamping ${toString (primaryWan.mtu - 40)}"
      "nat44 add interface address ${primaryWanInterface}"
    ]
    ++ map (z: "set interface nat44 in ${interfaceName z}") zones
    ++ ["set interface nat44 out ${primaryWanInterface}"]
    ++ map
    (publication: "nat44 add static mapping ${publication.protocol} local ${publication.target} ${toString publication.localPort} external ${primaryWanInterface} ${toString publication.externalPort}")
    publications
  );

  qosTos = className: production.qosClasses.${className}.dscp * 4;
  qosValues = lib.unique (map (z: qosTos z.qosClass) zones);
  qosMapEntries =
    lib.concatStringsSep " "
    (map (value: "[ip][${toString value}]=${toString value}") qosValues);
  qosCommands = lib.concatStringsSep "\n" (
    ["qos egress map id 0 ${qosMapEntries}"]
    ++ map (z: "qos store ip ${interfaceName z} value ${toString (qosTos z.qosClass)}") zones
    ++ map (z: "qos mark ip ${interfaceName z} id 0") zones
  );

  renderAclRule = rule:
    "${rule.action} src ${rule.src} dst ${rule.dst}"
    + lib.optionalString (rule ? proto) " proto ${toString rule.proto}"
    + lib.optionalString (rule ? sport) " sport ${toString rule.sport}"
    + lib.optionalString (rule ? dport) " dport ${toString rule.dport}";
  localIpv4Networks = map ipv4Network zones;
  localUlaNetworks = map ulaNetwork zones;
  trustedZones = map zone production.firewall.trustedInitiatorZones;
  trustedIpv4Networks = map ipv4Network trustedZones;
  trustedUlaNetworks = map ulaNetwork trustedZones;
  dhcp4Rule = {
    action = "permit";
    src = "0.0.0.0/32";
    dst = "255.255.255.255/32";
    proto = 17;
    sport = 68;
    dport = 67;
  };
  ingressRules = z:
    [dhcp4Rule]
    ++ lib.optionals (builtins.elem z.security ["restricted" "isolated"])
    (map (destination: {
        action = "deny";
        src = ipv4Network z;
        dst = destination;
      })
      localIpv4Networks)
    ++ [
      {
        action = "permit+reflect";
        src = ipv4Network z;
        dst = "0.0.0.0/0";
      }
    ]
    ++ lib.optionals (z.name == "lan") (map (source: {
        action = "permit+reflect";
        src = source;
        dst = "0.0.0.0/0";
      })
      controlPlane.routedIpv4)
    ++ lib.optionals (builtins.elem z.security ["restricted" "isolated"])
    (map (destination: {
        action = "deny";
        src = ulaNetwork z;
        dst = destination;
      })
      localUlaNetworks)
    ++ [
      {
        action = "permit";
        src = "fe80::/10";
        dst = "ff02::/16";
        proto = 58;
      }
      {
        # Strict IPv6 uRPF supplies the dynamic delegated-prefix anti-spoofing
        # which a static ACL cannot express.
        action = "permit+reflect";
        src = "::/0";
        dst = "::/0";
      }
    ]
    ++ lib.optionals (z.name == "lan") (map (source: {
        action = "permit+reflect";
        src = source;
        dst = "::/0";
      })
      controlPlane.routedIpv6)
    ++ [
      {
        action = "deny";
        src = "0.0.0.0/0";
        dst = "0.0.0.0/0";
      }
      {
        action = "deny";
        src = "::/0";
        dst = "::/0";
      }
    ];
  publicationRules = z:
    map
    (publication: {
      action = "permit";
      src = "0.0.0.0/0";
      dst = "${publication.target}/32";
      proto =
        if publication.protocol == "tcp"
        then 6
        else 17;
      dport = publication.localPort;
    })
    (lib.filter (publication: (zoneForAddress publication.target).name == z.name) publications);
  outputRules = z:
  # Permit same-zone Linux control-plane replies and traffic initiated by a
  # trusted/management zone.  New flows in the other direction reach the
  # final deny; reflected sessions are admitted by the ACL plugin first.
    [
      {
        action = "permit";
        src = ipv4Network z;
        dst = ipv4Network z;
      }
      {
        action = "permit";
        src = ulaNetwork z;
        dst = ulaNetwork z;
      }
    ]
    ++ map (source: {
      action = "permit";
      src = source;
      dst = ipv4Network z;
    }) (lib.filter (source: source != ipv4Network z) trustedIpv4Networks)
    ++ map (source: {
      action = "permit";
      src = source;
      dst = ulaNetwork z;
    }) (lib.filter (source: source != ulaNetwork z) trustedUlaNetworks)
    ++ lib.optionals (z.name == "lan") (lib.concatMap
      (destination:
        map (source: {
          action = "permit";
          src = source;
          dst = destination;
        })
        trustedIpv4Networks)
      controlPlane.routedIpv4)
    ++ lib.optionals (z.name == "lan") (lib.concatMap
      (destination:
        map (source: {
          action = "permit";
          src = source;
          dst = destination;
        })
        trustedUlaNetworks)
      controlPlane.routedIpv6)
    ++ publicationRules z
    ++ [
      {
        action = "permit";
        src = "::/0";
        dst = "::/0";
        proto = 58;
      }
      {
        action = "deny";
        src = "0.0.0.0/0";
        dst = "0.0.0.0/0";
      }
      {
        action = "deny";
        src = "::/0";
        dst = "::/0";
      }
    ];
  aclSpecs =
    [
      {
        name = "wan-input";
        rules = [
          {
            # NAT44-ED rejects IPv4 flows without state or a static mapping.
            action = "permit";
            src = "0.0.0.0/0";
            dst = "0.0.0.0/0";
          }
          {
            action = "permit";
            src = "::/0";
            dst = "::/0";
            proto = 58;
          }
          {
            action = "permit";
            src = "::/0";
            dst = "::/0";
            proto = 17;
            dport = 546;
          }
          {
            action = "deny";
            src = "::/0";
            dst = "::/0";
          }
        ];
      }
      {
        name = "wan-output";
        rules = [
          {
            action = "permit+reflect";
            src = "0.0.0.0/0";
            dst = "0.0.0.0/0";
          }
          {
            action = "permit+reflect";
            src = "::/0";
            dst = "::/0";
          }
        ];
      }
    ]
    ++ lib.concatMap
    (z: [
      {
        name = "${z.name}-input";
        rules = ingressRules z;
      }
      {
        name = "${z.name}-output";
        rules = outputRules z;
      }
    ])
    zones;
  aclIndices = lib.listToAttrs (lib.imap0 (index: acl: {
      name = acl.name;
      value = index;
    })
    aclSpecs);
  aclCommands = lib.concatStringsSep "\n" (map
    (acl: "set acl-plugin acl ${lib.concatStringsSep ", " (map renderAclRule acl.rules)} tag production-${acl.name}")
    aclSpecs);
  aclAttachmentCommands = lib.concatStringsSep "\n" (
    [
      "set acl-plugin interface ${primaryWanInterface} input acl ${toString aclIndices."wan-input"}"
      "set acl-plugin interface ${primaryWanInterface} output acl ${toString aclIndices."wan-output"}"
    ]
    ++ lib.concatMap
    (z: [
      "set acl-plugin interface ${interfaceName z} input acl ${toString aclIndices."${z.name}-input"}"
      "set acl-plugin interface ${interfaceName z} output acl ${toString aclIndices."${z.name}-output"}"
    ])
    zones
  );
  urpfCommands = lib.concatStringsSep "\n" (
    map (z: "set urpf ip6 rx ${interfaceName z} strict") zones
    ++ [
      "set urpf ip4 rx ${primaryWanInterface} loose"
      # DHCPv6-PD replies use the ISP router's link-local source. VPP's loose
      # IPv6 uRPF drops those packets before the WAN ACL, so the ACL supplies
      # the WAN boundary and strict IPv6 uRPF is kept only on inside zones.
    ]
  );
in {
  inherit platform primaryWanInterface backupWanInterface publications;
  requiredPlugins =
    [
      "acl_plugin.so"
      "dhcp_plugin.so"
      "nat_plugin.so"
      "ping_plugin.so"
      "urpf_plugin.so"
    ]
    ++ lib.optional useRdma "rdma_plugin.so"
    ++ lib.optional (platform.dataplane.driver == "dpdk") "dpdk_plugin.so";

  startupConfig = ''
    # INACTIVE PRODUCTION PLAN.  network.routing.production.enable must remain
    # false until the physical WAN cable move and reviewed CRS812 Safe Mode
    # transaction.  This is a complete replacement for the documentation lab,
    # not a script to append to the running VPP instance.
    ${lib.optionalString useRdma "create interface rdma host-if ${platform.dataInterface} name ${parent} num-rx-queues ${toString workerCount} mode ibv"}
    ${lib.optionalString useRdma "set interface mac address ${parent} ${platform.dataMac}"}
    set interface mtu packet 9000 ${parent}
    set interface state ${parent} up

    # Primary ISP: native DHCPv4, DHCPv6 IA_NA + PD, and RA-learned default.
    create sub-interfaces ${parent} ${toString primaryWan.vlanId}
    set interface mtu packet ${toString primaryWan.mtu} ${primaryWanInterface}
    set interface state ${primaryWanInterface} up
    set dhcp client intfc ${primaryWanInterface} hostname bluefield2
    ip6 nd address autoconfig ${primaryWanInterface} default-route
    dhcp6 client ${primaryWanInterface}
    dhcp6 pd client ${primaryWanInterface} prefix group ${prefixGroup}

    # Phone backup remains a control-only transit and receives no default or
    # NAT publication.  qBittorrent therefore cannot escape through it.
    create sub-interfaces ${parent} ${toString backupWan.vlanId}
    set interface mtu packet ${toString backupWan.mtu} ${backupWanInterface}
    set interface state ${backupWanInterface} up
    set interface ip address ${backupWanInterface} ${network.cidrOf "wanBackup" network.hosts.bluefield2.addresses.wanBackup}

    # Target security zones.  VLAN 10 is the future tagged replacement for the
    # still-flat LAN; none of these commands are active in the current lab.
    ${zoneInterfaceCommands}

    # The retired Linux router remains the DNS/DHCP/netboot/WireGuard host.
    # Route its tunnel networks through the new service address rather than
    # conflating that host with VPP's .1 gateway.
    ${controlPlaneRouteCommands}

    # Dynamic NAT address tracking makes every declared IPv4 publication
    # follow the DHCP lease.  Direct WAN SSH/Tor on the retired router is not
    # among the selected publication groups.
    ${natCommands}

    # Endpoints cannot promote themselves by setting DSCP.  VPP assigns the
    # class at zone ingress; the CRS812 trusts and schedules that marking.
    ${qosCommands}

    # IPv4 source prefixes are enforced in each zone ACL.  Dynamic delegated
    # IPv6 prefixes use strict uRPF.  Output ACLs reject new inter-zone flows,
    # while reflected state admits replies.  Primary-WAN IPv6 is default-deny
    # except ICMPv6 and DHCPv6; no NAT66 is used.
    ${urpfCommands}
    ${aclCommands}
    ${aclAttachmentCommands}
  '';

  healthScript = ''
    set -eu
    v4_ok=0
    v6_ok=0
    ${lib.concatMapStringsSep "\n" (target:
      if lib.hasInfix ":" target
      then ''
        if vppctl ping ${target} repeat 2 >/dev/null 2>&1; then
          v6_ok=1
        fi
      ''
      else ''
        if vppctl ping ${target} repeat 2 >/dev/null 2>&1; then
          v4_ok=1
        fi
      '')
    primaryWan.healthTargets}
    if [ "$v4_ok" -ne 1 ]; then
      echo "primary WAN has no reachable IPv4 health target" >&2
      exit 1
    fi
    if [ "$v6_ok" -ne 1 ]; then
      echo "primary WAN IPv6 is degraded (DHCPv4 remains healthy)" >&2
    fi
    vppctl show dhcp client intfc ${primaryWanInterface}
    vppctl show ip6 prefixes
  '';

  topologyJson = builtins.toJSON {
    enabled = production.enable;
    switch = production.switch;
    primaryWan = {
      inherit (primaryWan) vlanId mtu switchAccessPort lineRateMbps ethernet;
      bluefieldInterface = primaryWanInterface;
      ipv4 = primaryWan.ipv4.method;
      ipv6 = primaryWan.ipv6;
    };
    backupWan = {
      inherit (backupWan) vlanId mtu policy installDefaultRoute;
      bluefieldInterface = backupWanInterface;
    };
    zones =
      map (z: {
        inherit (z) name network vlanId ipv6SubnetId security qosClass;
        interface = interfaceName z;
        ipv4 = ipv4Gateway z;
        ula = ulaGateway z;
        delegatedSuffix = delegatedSuffix z;
      })
      zones;
    ipv6PublicationsEnabled = production.firewall.publishIpv6Services;
    publicationGroups = production.nat44.publicationGroups;
    controlPlane = {
      inherit (controlPlane) host targetIp targetIpv6 services routedIpv4 routedIpv6;
      viaInterface = interfaceName lanZone;
    };
  };
}
