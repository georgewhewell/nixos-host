{
  lib,
  network,
  driver ? "rdma",
  hostPfMode ? "off",
  hostPfEnable ? false,
}: let
  production = network.routing.production;
  transition = production.transition;
  platform = import ./vpp-platform.nix {
    inherit network driver hostPfMode;
  };
  parent = platform.dataName;

  primaryWan = production.wans.primary;
  primaryWanInterface = "${parent}.${toString primaryWan.vlanId}";
  backupWan = production.wans.backup;
  backupWanInterface = "${parent}.${toString backupWan.vlanId}";
  prefixGroup = primaryWan.ipv6.prefixGroup;
  controlPlane = transition.controlPlane;

  legacyVlans = map (name: network.vlans.${name} // {inherit name;}) transition.legacyInside.networks;
  legacyIpv4Networks = map (v: "${v.prefix}.0/${toString v.cidr}") legacyVlans;
  legacyIpv4Gateways = map (v: "${network.gatewayIp v.name}/${toString v.cidr}") legacyVlans;
  legacyUlaPrefix = "fdde:ad:${transition.legacyInside.ipv6SubnetId}";
  legacyUlaNetwork = "${legacyUlaPrefix}::/64";
  legacyUlaGateway = "${legacyUlaPrefix}::1/64";
  legacyDelegatedSuffix = "::${transition.legacyInside.delegatedSubnetId}:0:0:0:1/64";

  zone = name: let
    declaration = production.zones.${name};
    vlan = network.vlans.${declaration.network};
  in
    declaration
    // {
      inherit name vlan;
      mtu = declaration.mtu or (vlan.mtu or 1500);
    };
  taggedZones = map zone transition.taggedZones;
  interfaceName = z: "${parent}.${toString z.vlanId}";
  ipv4Network = z: "${z.vlan.prefix}.0/${toString z.vlan.cidr}";
  ipv4Gateway = z: "${network.gatewayIp z.network}/${toString z.vlan.cidr}";
  ulaPrefix = z: "fdde:ad:${z.ipv6SubnetId}";
  ulaNetwork = z: "${ulaPrefix z}::/64";
  ulaGateway = z: "${ulaPrefix z}::1/64";
  delegatedSuffix = z: "::${z.ipv6SubnetId}:0:0:0:1/64";

  workerCount = builtins.length platform.dataplane.workerCores;
  useRdma = platform.dataplane.driver == "rdma";

  taggedInterfaceCommands = lib.concatStringsSep "\n" (
    map (z: "create sub-interfaces ${parent} ${toString z.vlanId}") taggedZones
    ++ map (z: "set interface mtu packet ${toString z.mtu} ${interfaceName z}") taggedZones
    ++ map (z: "set interface state ${interfaceName z} up") taggedZones
    ++ map (z: "set interface ip address ${interfaceName z} ${ipv4Gateway z}") taggedZones
    ++ map (z: "set interface ip address ${interfaceName z} ${ulaGateway z}") taggedZones
    ++ map (z: "set ip6 address ${interfaceName z} prefix group ${prefixGroup} ${delegatedSuffix z}") taggedZones
    # VPP's CLI takes the maximum interval first, then the minimum.
    ++ map (z: "ip6 nd ${interfaceName z} ra-interval 60 30 ra-lifetime 180") taggedZones
    ++ map (z: "ip6 nd ${interfaceName z} prefix ${ulaNetwork z} 86400 14400") taggedZones
  );

  controlPlaneRouteCommands = lib.concatStringsSep "\n" (
    map (prefix: "ip route add ${prefix} via ${controlPlane.targetIp} ${parent}") controlPlane.routedIpv4
    ++ map (prefix: "ip route add ${prefix} via ${controlPlane.targetIpv6} ${parent}") controlPlane.routedIpv6
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
          publishIpv6 = production.firewall.publishIpv6Services && (forward.publishIpv6 or false);
          ipv6Endpoint = host.ipv6 or null;
        })
        (expandProtocols forward))
      host.forwards)
    selectedPublicationGroups);
  ipv6Publications = builtins.filter (p: p.publishIpv6) publications;

  natCommands = lib.concatStringsSep "\n" (
    [
      "set nat frame-queue-nelts ${toString production.nat44.frameQueueLength}"
      "nat44 plugin enable sessions ${toString production.nat44.sessions}"
      "nat mss-clamping ${toString (primaryWan.mtu - 40)}"
      "nat44 add interface address ${primaryWanInterface}"
      "set interface nat44 in ${parent}"
    ]
    ++ map (z: "set interface nat44 in ${interfaceName z}") taggedZones
    ++ ["set interface nat44 out ${primaryWanInterface}"]
    ++ map
    (p: "nat44 add static mapping ${p.protocol} local ${p.target} ${toString p.localPort} external ${primaryWanInterface} ${toString p.externalPort}")
    publications
  );

  qosTos = className: production.qosClasses.${className}.dscp * 4;
  qosInterfaces =
    [
      {
        interface = parent;
        qosClass = "bestEffort";
      }
    ]
    ++ map
    (z: {
      interface = interfaceName z;
      inherit (z) qosClass;
    })
    taggedZones;
  qosValues = lib.unique (map (i: qosTos i.qosClass) qosInterfaces);
  qosMapEntries = lib.concatStringsSep " " (map (value: "[ip][${toString value}]=${toString value}") qosValues);
  qosCommands = lib.concatStringsSep "\n" (
    ["qos egress map id 0 ${qosMapEntries}"]
    ++ map (i: "qos store ip ${i.interface} value ${toString (qosTos i.qosClass)}") qosInterfaces
    ++ map (i: "qos mark ip ${i.interface} id 0") qosInterfaces
  );

  renderAclRule = rule:
    "${rule.action} src ${rule.src} dst ${rule.dst}"
    + lib.optionalString (rule ? proto) " proto ${toString rule.proto}"
    + lib.optionalString (rule ? sport) " sport ${toString rule.sport}"
    + lib.optionalString (rule ? dport) " dport ${toString rule.dport}";
  dhcp4Rule = {
    action = "permit";
    src = "0.0.0.0/32";
    dst = "255.255.255.255/32";
    proto = 17;
    sport = 68;
    dport = 67;
  };
  ipv6ControlRules = [
    {
      action = "permit";
      src = "fe80::/10";
      dst = "ff02::/16";
      proto = 58;
    }
    {
      action = "permit";
      src = "::/0";
      dst = "::/0";
      proto = 58;
    }
  ];
  finalDenyRules = [
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
  publicationRules =
    map (p: {
      action = "permit";
      src = "0.0.0.0/0";
      dst = "${p.target}/32";
      proto =
        if p.protocol == "tcp"
        then 6
        else 17;
      dport = p.localPort;
    })
    publications;
  ipv6AddressToken = group: "@ipv6-${group}@";
  ipv6PublicationRules =
    map (p: {
      action = "permit";
      src = "::/0";
      dst = "${ipv6AddressToken p.group}/128";
      proto =
        if p.protocol == "tcp"
        then 6
        else 17;
      dport = p.localPort;
    })
    ipv6Publications;
  trustedIpv4Sources = legacyIpv4Networks ++ map ipv4Network taggedZones;
  trustedUlaSources = [legacyUlaNetwork] ++ map ulaNetwork taggedZones;
  hostPfIpv4Network =
    "${network.vlans.${network.routing.hostPf.network}.prefix}.0/"
    + toString network.vlans.${network.routing.hostPf.network}.cidr;
  fabricIpv4Network =
    "${network.vlans.fabric.prefix}.0/${toString network.vlans.fabric.cidr}";

  legacyInputRules =
    [dhcp4Rule]
    ++ map (source: {
      action = "permit+reflect";
      src = source;
      dst = "0.0.0.0/0";
    })
    (legacyIpv4Networks ++ controlPlane.routedIpv4)
    ++ ipv6ControlRules
    ++ map (source: {
      action = "permit+reflect";
      src = source;
      dst = "::/0";
    })
    ([legacyUlaNetwork] ++ controlPlane.routedIpv6)
    # The delegated GUA is dynamic. Strict IPv6 uRPF on the legacy parent
    # proves that a source belongs to a prefix currently routed through this
    # interface before this stateful permit admits its outbound flow.
    ++ [
      {
        action = "permit+reflect";
        src = "::/0";
        dst = "::/0";
      }
    ]
    ++ finalDenyRules;
  # Reflected sessions established by the inside input ACL are admitted before
  # this stateless output list.  These explicit permits therefore describe
  # only new trusted cross-zone flows; do not add a blanket IPv6 output rule.
  legacyOutputRulesFor = extraIpv6PublicationRules:
    lib.concatMap
    (destination:
      map (source: {
        action = "permit";
        src = source;
        dst = destination;
      })
      trustedIpv4Sources)
    (legacyIpv4Networks ++ controlPlane.routedIpv4)
    ++ lib.concatMap
    (destination:
      map (source: {
        action = "permit";
        src = source;
        dst = destination;
      })
      trustedUlaSources)
    ([legacyUlaNetwork] ++ controlPlane.routedIpv6)
    ++ lib.optionals hostPfEnable [
      {
        # The optional PCIe shortcut is deliberately narrower than a normal
        # trusted zone: it may reach only the high-speed fabric during tests.
        action = "permit";
        src = hostPfIpv4Network;
        dst = fabricIpv4Network;
      }
    ]
    ++ publicationRules
    ++ extraIpv6PublicationRules
    ++ ipv6ControlRules
    ++ finalDenyRules;
  legacyOutputRules = legacyOutputRulesFor [];
  taggedInputRules = z:
    [dhcp4Rule]
    ++ [
      {
        action = "permit+reflect";
        src = ipv4Network z;
        dst = "0.0.0.0/0";
      }
    ]
    ++ ipv6ControlRules
    # The ISP-delegated source changes at runtime. Strict IPv6 uRPF below
    # proves it arrived through this interface before the reflected permit.
    ++ [
      {
        action = "permit+reflect";
        src = "::/0";
        dst = "::/0";
      }
    ]
    ++ finalDenyRules;
  taggedOutputRules = z:
    map (source: {
      action = "permit";
      src = source;
      dst = ipv4Network z;
    })
    trustedIpv4Sources
    ++ map (source: {
      action = "permit";
      src = source;
      dst = ulaNetwork z;
    })
    trustedUlaSources
    ++ ipv6ControlRules
    ++ finalDenyRules;

  aclSpecs =
    [
      {
        name = "wan-input";
        rules = [
          {
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
      {
        name = "legacy-input";
        rules = legacyInputRules;
      }
      {
        name = "legacy-output";
        rules = legacyOutputRules;
      }
    ]
    ++ lib.concatMap (z: [
      {
        name = "${z.name}-input";
        rules = taggedInputRules z;
      }
      {
        name = "${z.name}-output";
        rules = taggedOutputRules z;
      }
    ])
    taggedZones;
  aclIndices = lib.listToAttrs (lib.imap0 (index: acl: {
      name = acl.name;
      value = index;
    })
    aclSpecs);
  dynamicIpv6AclPolicy = {
    inherit prefixGroup;
    publications =
      map (p: {
        token = ipv6AddressToken p.group;
        inherit (p) group protocol localPort externalPort;
        inherit (p.ipv6Endpoint) interfaceMac subnetId;
      })
      ipv6Publications;
    acls = [
      {
        index = aclIndices."wan-input";
        tag = "transition-wan-input";
        rules =
          [
            {
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
          ]
          ++ ipv6PublicationRules
          ++ [
            {
              action = "deny";
              src = "::/0";
              dst = "::/0";
            }
          ];
      }
      {
        index = aclIndices."legacy-output";
        tag = "transition-legacy-output";
        rules = legacyOutputRulesFor ipv6PublicationRules;
      }
    ];
  };
  aclCommands = lib.concatStringsSep "\n" (map
    (acl: "set acl-plugin acl ${lib.concatStringsSep ", " (map renderAclRule acl.rules)} tag transition-${acl.name}")
    aclSpecs);
  aclAttachmentCommands = lib.concatStringsSep "\n" (
    [
      "set acl-plugin interface ${primaryWanInterface} input acl ${toString aclIndices."wan-input"}"
      "set acl-plugin interface ${primaryWanInterface} output acl ${toString aclIndices."wan-output"}"
      "set acl-plugin interface ${parent} input acl ${toString aclIndices."legacy-input"}"
      "set acl-plugin interface ${parent} output acl ${toString aclIndices."legacy-output"}"
    ]
    ++ lib.concatMap (z: [
      "set acl-plugin interface ${interfaceName z} input acl ${toString aclIndices."${z.name}-input"}"
      "set acl-plugin interface ${interfaceName z} output acl ${toString aclIndices."${z.name}-output"}"
    ])
    taggedZones
  );
  urpfCommands = lib.concatStringsSep "\n" (
    [
      "set urpf ip6 rx ${parent} strict"
      "set urpf ip4 rx ${primaryWanInterface} loose"
      # Do not enable IPv6 uRPF on the WAN. DHCPv6-PD replies originate from
      # the ISP router's link-local address; VPP's loose uRPF feature rejects
      # that source before the WAN ACL can admit UDP/546. The WAN IPv6 ACL is
      # the ingress boundary here, while strict uRPF remains on inside links.
    ]
    ++ map (z: "set urpf ip6 rx ${interfaceName z} strict") taggedZones
  );
in {
  inherit platform primaryWanInterface backupWanInterface publications ipv6Publications dynamicIpv6AclPolicy;
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
    # INACTIVE TRANSITION PLAN. This replaces the lab only during the reviewed
    # gateway handoff; it is never appended to a running VPP instance.
    ${lib.optionalString useRdma "create interface rdma host-if ${platform.dataInterface} name ${parent} num-rx-queues ${toString workerCount} mode ibv"}
    ${lib.optionalString useRdma "set interface mac address ${parent} ${platform.dataMac}"}
    set interface mtu packet ${toString transition.legacyInside.mtu} ${parent}
    set interface state ${parent} up

    # Transitional inside: preserve the existing untagged LAN/fabric L2 and
    # take both gateway addresses only after the Linux router releases them.
    ${lib.concatStringsSep "\n" (map (address: "set interface ip address ${parent} ${address}") legacyIpv4Gateways)}
    set interface ip address ${parent} ${legacyUlaGateway}
    ip6 nd ${parent} ra-interval 60 30 ra-lifetime 180
    ip6 nd ${parent} prefix ${legacyUlaNetwork} 86400 14400

    # Primary ISP stays isolated in tagged VLAN 100 on the shared data port.
    create sub-interfaces ${parent} ${toString primaryWan.vlanId}
    set interface mtu packet ${toString primaryWan.mtu} ${primaryWanInterface}
    set interface state ${primaryWanInterface} up
    set dhcp client intfc ${primaryWanInterface} hostname bluefield2
    ip6 nd address autoconfig ${primaryWanInterface} default-route
    dhcp6 client ${primaryWanInterface}
    dhcp6 pd client ${primaryWanInterface} prefix group ${prefixGroup}

    # Register delegated-prefix consumers only after the WAN creates the
    # prefix group.  The prefix itself may arrive later without a CLI race.
    set ip6 address ${parent} prefix group ${prefixGroup} ${legacyDelegatedSuffix}

    # Keep the recovery transit address reachable for diagnostics, but never
    # install an Internet default or NAT pool through it. K3 and its iPhone are
    # an out-of-band recovery endpoint, not a second VPP WAN.
    create sub-interfaces ${parent} ${toString backupWan.vlanId}
    set interface mtu packet ${toString backupWan.mtu} ${backupWanInterface}
    set interface state ${backupWanInterface} up
    set interface ip address ${backupWanInterface} ${network.cidrOf "wanBackup" network.hosts.bluefield2.addresses.wanBackup}

    # Only already-live client VLANs move during phase one. Future zones stay
    # deferred until the flat gateway has passed its acceptance period.
    ${taggedInterfaceCommands}

    # DNS/DHCP/netboot/WireGuard stay on the old router at .31. The routes
    # preserve replies to its tunnel clients after VPP becomes the gateway.
    ${controlPlaneRouteCommands}

    ${natCommands}
    ${qosCommands}
    ${urpfCommands}
    ${aclCommands}
    ${aclAttachmentCommands}
  '';

  healthScript = ''
    set -eu
    vppctl show dhcp client intfc ${primaryWanInterface}
    vppctl show ip6 prefixes
    vppctl show ip fib 0.0.0.0/0
    vppctl ping ${controlPlane.targetIp} repeat 2
    vppctl ping ${network.primaryIp network.hosts.trex} repeat 2
  '';

  topologyJson = builtins.toJSON {
    enabled = transition.enable;
    mode = transition.mode;
    switch = production.switch // transition.switch;
    primaryWan = {
      inherit (primaryWan) vlanId mtu switchAccessPort lineRateMbps ethernet;
      bluefieldInterface = primaryWanInterface;
    };
    backupWan = {
      inherit (backupWan) vlanId mtu policy;
      bluefieldInterface = backupWanInterface;
      managedDefaultRoute = false;
      routingRole = "none";
    };
    legacyInside = {
      interface = parent;
      inherit (transition.legacyInside) networks mtu ipv6SubnetId delegatedSubnetId;
      ipv4Gateways = legacyIpv4Gateways;
      ula = legacyUlaGateway;
      delegatedSuffix = legacyDelegatedSuffix;
    };
    taggedZones =
      map (z: {
        inherit (z) name network vlanId qosClass security;
        interface = interfaceName z;
        ipv4 = ipv4Gateway z;
      })
      taggedZones;
    deferredFinalZones = transition.deferredFinalZones;
    controlPlane = {
      inherit (controlPlane) host targetIp targetIpv6 services routedIpv4 routedIpv6;
    };
    publicationGroups = production.nat44.publicationGroups;
    publications = publications;
  };
}
