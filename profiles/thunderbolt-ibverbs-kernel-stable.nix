{ pkgs
, lib
, inputs
, ...
}:
let
  thunderboltIbverbs = inputs.nix-strix-halo.inputs.thunderbolt-ibverbs;
  usb4KernelPatches =
    builtins.filter
      (patch: patch.name != "usb4-nhi-ring-debugfs-instrumentation")
      thunderboltIbverbs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.usb4KernelPatches;
  localKernelPatches = [
    {
      name = "thunderbolt-nhi-ring-throttling-helper";
      patch = ./patches/thunderbolt-nhi-ring-throttling-helper.patch;
    }
  ];

  # Stable 7.0.x from nixpkgs (latest), patched. For hosts that need ZFS -
  # ZFS upstream currently caps at kernel 7.0, so the 7.1-rc1 variant of this
  # profile breaks the zfs-kernel build. The usb4-stream / CONFIGFS additions
  # are still picked up because they're applied as kernelPatches on top of
  # whatever the base release ships.
  linuxPackagesUsb4 = pkgs.linuxPackages_latest.extend (self: super: {
    kernel = super.kernel.override {
      kernelPatches = (super.kernel.kernelPatches or [ ]) ++ usb4KernelPatches ++ localKernelPatches;
      structuredExtraConfig = with lib.kernel; {
        USB4_DEBUGFS_WRITE = yes;
      };
    };
  });
in
{
  boot.kernelPackages = lib.mkOverride 900 linuxPackagesUsb4;
}
