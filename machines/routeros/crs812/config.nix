# CRS812 resources safe for staged nix-routeros ownership.
#
# This file is consumed by machines/routeros/crs812/terranix.nix. It does not
# replace config.rsc: switch-chip L3HW, QoS/PFC/tx-manager, and the deliberately
# conservative migration sequencing remain owned by config.rsc until provider
# support and a production import have been verified.
{
  network,
  phase ? "final",
}: let
  production = network.routing.production;
  transition = production.transition;
  isAdoption = phase == "adoption";
  isTransition = phase == "transition";
  isCutover = phase == "cutover";
  isLegacyHandoff = isTransition || isCutover;
  primaryWan = production.wans.primary;
  primaryWanPort = primaryWan.switchAccessPort;
  backupWan = production.wans.backup;
  servicePlaneTrunk = transition.controlPlane.switchPort;
  bluefieldTrunk = production.switch.bluefieldTrunk;
  bridgePorts = [
    "ether1"
    "ether2"
    "qsfp56-1-1"
    "qsfp56-1-2"
    "qsfp56-1-3"
    "qsfp56-1-4"
    "qsfp56-2-1"
    "qsfp56-2-2"
    "qsfp56-2-3"
    "qsfp56-2-4"
    "qsfp56-dd-1-1"
    "qsfp56-dd-1-2"
    "qsfp56-dd-1-3"
    "qsfp56-dd-1-4"
    "qsfp56-dd-1-5"
    "qsfp56-dd-1-6"
    "qsfp56-dd-1-7"
    "qsfp56-dd-1-8"
    "qsfp56-dd-2-1"
    "qsfp56-dd-2-2"
    "qsfp56-dd-2-3"
    "qsfp56-dd-2-4"
    "qsfp56-dd-2-5"
    "qsfp56-dd-2-6"
    "qsfp56-dd-2-7"
    "qsfp56-dd-2-8"
    "sfp56-1"
    "sfp56-2"
    "sfp56-3"
    "sfp56-4"
    "sfp56-5"
    "sfp56-6"
    "sfp56-7"
    "sfp56-8"
  ];
in {
  routeros = {
    connection = {
      gateway = "192.168.23.27";
      username = "admin";
      providerVersion = "~> 1.99";
      scheme = "api";
    };

    network = {
      subnet = "192.168.23.0/24";
      dhcp.server.enable = false;
      dhcp.client.enable = false;
    };

    interfaces = {
      # Read-only inventory 2026-08-28: the backup hybrid uplink is Rock
      # ether1 and the BlueField-2 is qsfp56-1-1. Keep physical resource
      # emission gated until each object has been imported.
      wan = [];
      manageLists = false;
      manageEthernetSettings = false;
    };

    system = {
      identity = "mikrotik-crs812";
      ipAddressComment = "nixos-config-lan-mgmt";
      timezone = "Europe/Zurich";
      timezoneAutodetect = true;
      ipv6.enable = true;
      ipv6.acceptRouterAdvertisements = "yes-if-forwarding-disabled";
      ipv6.maxNeighborEntries = 16384;
      ipSettings.maxNeighborEntries = 16384;
      neighborDiscovery = {
        # Provider 1.99.1 cannot import this RouterOS 7.24 singleton: its read
        # response has no usable ID. Keep it outside phase-one ownership.
        manage = false;
        interfaceList = "static";
      };
      macServer.allowedInterfaceList = "all";
      bfd.manage = false;
      ipsec.dpdInterval = "8s";
      ipsec.dpdMaxFailures = 4;
      services = {
        # Provider 1.99.1 resolves live /ip service rows and then loses their
        # identities during import. Keep the current values documented below,
        # but emit no service resources until that provider bug is fixed.
        manage = false;
        ftp.enable = true;
        telnet.enable = true;
        www.enable = true;
        api-ssl.enable = false;
        # Mirror the unrestricted live values for import. Restricting these is
        # a later Safe Mode hardening change, not part of state adoption.
        ssh.allowedAddresses = null;
        winbox.allowedAddresses = null;
        api.allowedAddresses = null;
      };
    };

    bridge = {
      enable = true;
      comment = "nixos-config: hardware fabric bridge";
      adminMac = "38:32:7A:14:FF:67";
      mtu = 9000;
      portCostMode = "long";
      protocolMode = "rstp";
      # Keep disabled until the complete production table is imported and the
      # exact WAN/SFP cabling map is confirmed.
      # The transition renderer stays non-operative for review.  The separate
      # cutover renderer is the only phase that turns filtering on; without
      # filtering an ISP frame entering sfp56-8 would leak into the flat LAN
      # instead of being translated to tagged VLAN 100 for BlueField.
      vlanFiltering = isCutover;
      managePorts = false;
      manageVlanEntries = false;
      ports = bridgePorts;
      portSettings =
        builtins.listToAttrs (map (interface: {
            name = interface;
            value = {
              pvid = 1;
              ingressFiltering = true;
              frameTypes = "admit-all";
              hw = true;
              comment = "defconf";
            };
          })
          bridgePorts)
        // (
          if isAdoption
          then {}
          else {
            # Desired cut-over state only; managePorts=false keeps this away
            # from the live bridge.  The ISP sees an ordinary untagged handoff.
            ${primaryWanPort} = {
              pvid = primaryWan.vlanId;
              ingressFiltering = true;
              frameTypes = "admit-only-untagged-and-priority-tagged";
              hw = true;
              comment = "nixos-config: primary ISP access (planned)";
            };
            # Production VPP has no untagged data-plane network.  This becomes
            # tagged-only only with the complete VLAN table and lab removal.
            ${bluefieldTrunk} = {
              pvid =
                if isLegacyHandoff
                then transition.switch.legacyPvid
                else 1;
              ingressFiltering = true;
              frameTypes =
                if isLegacyHandoff
                then "admit-all"
                else "admit-only-vlan-tagged";
              hw = true;
              comment =
                if isLegacyHandoff
                then "nixos-config: BlueField hybrid transition (planned)"
                else "nixos-config: BlueField VPP trunk (planned)";
            };
          }
        );
      vlanEntries =
        [
        ]
        ++ (
          if isAdoption
          then []
          else [
            {
              name = "primary-wan";
              vlanIds = [(toString primaryWan.vlanId)];
              tagged = [bluefieldTrunk];
              untagged = [primaryWanPort];
              # Deliberately no `bridge` member: the switch CPU must never join
              # the ISP broadcast domain.
              comment = "nixos-config: primary WAN access -> BlueField only (planned)";
            }
          ]
        )
        ++ (
          if isLegacyHandoff
          then [
            {
              # WiFi VLAN 50 crosses CRS804/CRS510. Carry it both to VPP and to
              # the old router's service plane, where dnsmasq remains during
              # the transition.
              name = "transition-wifi";
              vlanIds = [(toString network.vlans.wifi.id)];
              tagged = [transition.switch.legacyUplink bluefieldTrunk servicePlaneTrunk];
              comment = "nixos-config: existing WiFi VLAN -> VPP transition (planned)";
            }
          ]
          else []
        )
        ++ [
          {
            name = "vpp-lab";
            vlanIds = ["3901-3903"];
            tagged = [production.switch.lanFabricTrunk bluefieldTrunk];
            comment = "nixos-config: VPP lab VLANs";
          }
        ]
        ++ (
          if isAdoption || !backupWan.switchTransit.enable
          then []
          else [
            {
              # The edge port is resolved once in network.nix from the live
              # switch FDB; carry the tag only between that downlink and VPP.
              name = "backup-transit";
              vlanIds = ["101"];
              tagged = [backupWan.switchTransit.edgePort bluefieldTrunk];
              comment = "nixos-config: backup transit VLAN 101 (planned)";
            }
          ]
        );
    };

    interfaces.ethernetSettings = {
      # Verified live: BlueField-2 p0 is this port at 100G CR4/RS-FEC.
      "qsfp56-1-1" = {
        name = "qsfp56-1-1";
        ignoreFactoryNameDrift = true;
        comment = "nixos-config: bluefield2 p0 100G lab";
        autoNegotiation = false;
        speed = "100G-baseCR4";
        fecMode = "fec91";
        mtu = 9000;
        l2mtu = 9216;
      };
      ${primaryWanPort} = {
        name = primaryWanPort;
        ignoreFactoryNameDrift = true;
        autoNegotiation =
          if isAdoption
          then true
          else primaryWan.ethernet.autoNegotiation;
        speed =
          if isAdoption
          then null
          else primaryWan.ethernet.speed;
        fecMode =
          if isAdoption
          then "auto"
          else primaryWan.ethernet.fecMode;
        mtu =
          if isAdoption
          then 9000
          else primaryWan.mtu;
        l2mtu = 9216;
      };
    };

    # The provider has a clean schema for these switch-wide flags. QoS
    # profiles, tx-manager queues, and PFC remain in config.rsc.
    switch = {
      enable = true;
      name = "switch1";
      l3HwOffloading = true;
      qosHwOffloading = true;
    };

    dns.enable = false;
    firewall.enable = false;
    wifi.enable = false;
  };

  # The switch is the live 192.168.25.1 fabric gateway today (resource ID
  # *6).  Keep it enabled in adoption/review phases, then disable—not
  # delete—it at cutover so VPP can take the address and rollback remains a
  # one-property operation.
  resource.routeros_ip_address.fabric_gateway = {
    address = "${network.gatewayIp "fabric"}/${toString network.vlans.fabric.cidr}";
    network = "${network.vlans.fabric.prefix}.0";
    interface = "bridge";
    comment = "nixos-config: fabric gateway";
    disabled = isCutover;
  };
}
