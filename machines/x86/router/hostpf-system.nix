{
  imports = [ ./service-cutover-system.nix ];

  # The BlueField PF is an optional, source-selected fabric shortcut. Copper
  # LAN, DNS, DHCP, WireGuard, and the router's default route remain usable
  # when either the DPU or its PCIe function is absent.
  bluefieldHostPf.routerMode = "source-policy";
}
