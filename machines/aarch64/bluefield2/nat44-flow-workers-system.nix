{
  imports = [./hostpf-system.nix];

  # Experimental review closure. Established NAT44-ED sessions still follow
  # the global flow table, while new dynamic sessions from one LAN address are
  # spread across workers by their complete endpoint-dependent flow key. The
  # ordinary bluefield2-cross target remains the unpatched rollback closure.
  bluefield2.vpp.nat44FlowWorkers.enable = true;
}
