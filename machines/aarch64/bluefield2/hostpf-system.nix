{
  imports = [ ./transition-system.nix ];

  # Verified production dataplane: the mlx5 PMD owns the physical uplink and
  # its external-host PF representor while the kernel retains the bifurcated
  # Verbs control path.  Keep this guard-free; hostpf-staged-system.nix wraps
  # the same closure when an attended boot guard is wanted.
  bluefield2.hostPf.mode = "vpp-representor";
  bluefield2.vpp.dataplaneDriver = "dpdk";
}
