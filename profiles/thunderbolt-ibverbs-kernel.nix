{ pkgs
, lib
, inputs
, ...
}:
let
  thunderboltIbverbs = inputs.thunderbolt-ibverbs-kernel;
  thunderboltPatchSet =
    thunderboltIbverbs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  thunderboltKernelPatches =
    thunderboltPatchSet.portableKernelPatches or thunderboltPatchSet.kernelPatches;
  linuxPackagesThunderbolt = pkgs.linuxPackages_latest.extend (self: super: {
    kernel = super.kernel.override {
      kernelPatches = (super.kernel.kernelPatches or [ ]) ++ thunderboltKernelPatches;
      structuredExtraConfig = with lib.kernel; {
        USB4_DEBUGFS_WRITE = yes;
      };
    };
  });
in
{
  # The thunderbolt-ibverbs NixOS module is brought in by
  # `nix-strix-halo.nixosModules.default`, pinned via
  # `inputs.thunderbolt-ibverbs.follows = "thunderbolt-ibverbs-kernel"`
  # in the top-level flake. Re-importing it here causes an
  # already-declared error on `hardware.thunderbolt-ibverbs.enable`.

  boot.kernelPackages = lib.mkOverride 900 linuxPackagesThunderbolt;
  boot.extraModprobeConfig = ''
    options thunderbolt xdomain_lane_bonding=0 xdomain_debug=1 xdomain_bridge_pad=0 xdomain_bridge_sideband=1 xdomain_bridge_properties_retries=1 xdomain_bridge_properties_chunk=0
    options thunderbolt_net e2e=0 tx_e2e=0 throttling=32000
  '';

  hardware.thunderbolt-ibverbs.enable = true;
}
