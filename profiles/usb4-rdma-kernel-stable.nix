{
  pkgs,
  lib,
  inputs,
  ...
}: let
  usb4KernelPatches = inputs.usb4-rdma.legacyPackages.${pkgs.stdenv.hostPlatform.system}.usb4KernelPatches;

  # Stable 7.0.x from nixpkgs (latest), patched. For hosts that need ZFS —
  # ZFS upstream currently caps at kernel 7.0, so the 7.1-rc1 variant of this
  # profile breaks the zfs-kernel build. The usb4-stream / CONFIGFS additions
  # are still picked up because they're applied as kernelPatches on top of
  # whatever the base release ships.
  linuxPackagesUsb4 = pkgs.linuxPackages_latest.extend (self: super: {
    kernel = super.kernel.override {
      kernelPatches = (super.kernel.kernelPatches or []) ++ usb4KernelPatches;
      structuredExtraConfig = with lib.kernel; {
        USB4_CONFIGFS = module;
        USB4_DEBUGFS_WRITE = yes;
        USB4_STREAM = module;
      };
    };
  });
in {
  boot.kernelPackages = lib.mkOverride 900 linuxPackagesUsb4;
}
