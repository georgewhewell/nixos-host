{ pkgs
, lib
, inputs
, ...
}:
let
  thunderboltIbverbs = inputs.nix-strix-halo.inputs.thunderbolt-ibverbs;
  thunderboltPatchSet =
    thunderboltIbverbs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  thunderboltKernelPatches =
    (thunderboltPatchSet.portableKernelPatches or thunderboltPatchSet.kernelPatches)
    ++ (thunderboltPatchSet.integrationDebugKernelPatches or [ ]);

  # Stable 7.0.x from nixpkgs (latest), patched. For hosts that need ZFS -
  # ZFS upstream currently caps at kernel 7.0, so the 7.1-rc1 variant of this
  # profile breaks the zfs-kernel build. The usb4-stream / CONFIGFS additions
  # are still picked up because they're applied as kernelPatches on top of
  # whatever the base release ships.
  linuxPackagesUsb4 = pkgs.linuxPackages_latest.extend (self: super: {
    kernel = super.kernel.override {
      kernelPatches = (super.kernel.kernelPatches or [ ]) ++ thunderboltKernelPatches;
      structuredExtraConfig = with lib.kernel; {
        USB4_DEBUGFS_WRITE = yes;
      };
    };
  });
in
{
  boot.kernelPackages = lib.mkOverride 900 linuxPackagesUsb4;
  boot.extraModprobeConfig = ''
    options thunderbolt xdomain_lane_bonding=0 xdomain_debug=1
    options thunderbolt_net e2e=0 tx_e2e=0 throttling=32000
  '';
}
