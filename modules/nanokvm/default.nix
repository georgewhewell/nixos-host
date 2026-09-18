# The fleet imports every top-level modules/ entry. Deployment compositions
# are selected explicitly from fleet.nix by machines/default.nix, never
# enabled for unrelated machines merely by this directory existing.
{ ... }: { }
