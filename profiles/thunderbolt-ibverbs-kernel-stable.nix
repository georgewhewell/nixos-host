{ pkgs
, lib
, inputs
, ...
}:
let
  thunderboltIbverbs = inputs.nix-strix-halo.inputs.thunderbolt-ibverbs;
  thunderboltPatchSet =
    thunderboltIbverbs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  baseKernelPatches =
    (thunderboltPatchSet.portableKernelPatches or thunderboltPatchSet.kernelPatches)
    ++ (thunderboltPatchSet.integrationDebugKernelPatches or [ ]);

  # `usb4-xdomain-property-identity-match` was upstreamed into Linux 7.1: the
  # mainline tree already carries the pkg_len plumbing and the uuid_equal()
  # identity check in tb_xdomain_match, so the out-of-tree patch reverse-applies
  # and aborts the kernel build. Drop it on >= 7.1 (the other 29 patches still
  # apply cleanly). Keep it on older kernels in case one is ever pinned back.
  kernelVersion = pkgs.linuxPackages_latest.kernel.version;
  thunderboltKernelPatches =
    if lib.versionAtLeast kernelVersion "7.1"
    then lib.filter (p: (p.name or "") != "usb4-xdomain-property-identity-match") baseKernelPatches
    else baseKernelPatches;

  # nixpkgs latest, patched, on kernel 7.1. ZFS support comes from the
  # openzfs 2.4.99 override in flake.nix (Linux-Maximum: 7.1). The usb4-stream /
  # CONFIGFS additions are applied as kernelPatches on top of the base release.
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
