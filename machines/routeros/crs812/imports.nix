# Existing IDs discovered read-only on 2026-08-28 (RouterOS 7.24rc4).
#
# Phase one emits only resources with stable provider import semantics. Bridge
# ports, VLAN rows, and physical Ethernet resources are configured in
# config.nix but gated off until their full ownership set is imported.
{config, lib, ...}: let
  bridgePortIds = {
    ether1 = "*0";
    ether2 = "*1";
    "qsfp56-1-1" = "*2";
    "qsfp56-1-2" = "*3";
    "qsfp56-1-3" = "*4";
    "qsfp56-1-4" = "*5";
    "qsfp56-2-1" = "*6";
    "qsfp56-2-2" = "*7";
    "qsfp56-2-3" = "*8";
    "qsfp56-2-4" = "*9";
    "qsfp56-dd-1-1" = "*A";
    "qsfp56-dd-1-2" = "*B";
    "qsfp56-dd-1-3" = "*C";
    "qsfp56-dd-1-4" = "*D";
    "qsfp56-dd-1-5" = "*E";
    "qsfp56-dd-1-6" = "*F";
    "qsfp56-dd-1-7" = "*10";
    "qsfp56-dd-1-8" = "*11";
    "qsfp56-dd-2-1" = "*12";
    "qsfp56-dd-2-2" = "*13";
    "qsfp56-dd-2-3" = "*14";
    "qsfp56-dd-2-4" = "*15";
    "qsfp56-dd-2-5" = "*16";
    "qsfp56-dd-2-6" = "*17";
    "qsfp56-dd-2-7" = "*18";
    "qsfp56-dd-2-8" = "*19";
    "sfp56-1" = "*1A";
    "sfp56-2" = "*1B";
    "sfp56-3" = "*1C";
    "sfp56-4" = "*1D";
    "sfp56-5" = "*1E";
    "sfp56-6" = "*1F";
    "sfp56-7" = "*20";
    "sfp56-8" = "*21";
  };
  stableImports = [
    {
      to = "routeros_interface_bridge.bridge";
      id = "*24";
    }
    {
      to = "routeros_ip_address.bridge";
      id = "*2";
    }
    {
      # Live 192.168.25.1/24 fabric gateway.  The cutover phase disables this
      # resource when BlueField assumes the address; it stays in state for an
      # immediate rollback.
      to = "routeros_ip_address.fabric_gateway";
      id = "*6";
    }
    {
      to = "routeros_system_identity.router";
      id = ".";
    }
    {
      to = "routeros_system_clock.default";
      id = ".";
    }
    {
      to = "routeros_ip_settings.default";
      id = ".";
    }
    {
      to = "routeros_ipv6_settings.default";
      id = ".";
    }
    {
      to = "routeros_ip_ipsec_profile.default";
      id = "*A";
    }
    {
      to = "routeros_tool_mac_server.default";
      id = ".";
    }
    {
      to = "routeros_tool_mac_server_winbox.default";
      id = ".";
    }
    {
      to = "routeros_interface_ethernet_switch.switch1";
      id = "*0";
    }
  ];
  portImports = lib.mapAttrsToList (interface: id: {
    to = "routeros_interface_bridge_port.${interface}";
    inherit id;
  }) bridgePortIds;
  vlanImports = [
    {
      to = "routeros_interface_bridge_vlan.vpp-lab";
      id = "*2";
    }
  ];
  ethernetImports = [
    {
      to = "routeros_interface_ethernet.qsfp56-1-1";
      id = "*14";
    }
    {
      to = "routeros_interface_ethernet.sfp56-8";
      id = "*23";
    }
  ];
in {
  import = stableImports
    ++ lib.optionals config.routeros.bridge.managePorts portImports
    ++ lib.optionals config.routeros.bridge.manageVlanEntries vlanImports
    ++ lib.optionals config.routeros.interfaces.manageEthernetSettings ethernetImports;
}
