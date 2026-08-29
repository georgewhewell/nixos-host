{
  imports = [./hostpf-system.nix];

  # Review-only production-plus-lab closure. CNAT is loaded and sized at VPP
  # startup, but its feature arc remains detached until the operator manually
  # starts bluefield-vpp-cnat-lab.service. The normal bluefield2-cross target
  # remains the production rollback closure.
  services.bluefield2-vpp-cnat-lab.enable = true;
}
