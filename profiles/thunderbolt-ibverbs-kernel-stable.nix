{ pkgs
, lib
, inputs
, ...
}:
let
  thunderboltIbverbs = inputs.nix-strix-halo.inputs.thunderbolt-ibverbs;
  thunderboltKernelPatches =
    thunderboltIbverbs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.portableKernelPatches;
  localThunderboltKernelPatches = [
    {
      name = "thunderbolt-xdomain-lane-bonding-param";
      patch = ./patches/thunderbolt-xdomain-lane-bonding-param.patch;
    }
    {
      name = "thunderbolt-xdomain-properties-debug";
      patch = ./patches/thunderbolt-xdomain-properties-debug.patch;
    }
    {
      name = "thunderbolt-xdomain-route-properties-param";
      patch = ./patches/thunderbolt-xdomain-route-properties-param.patch;
    }
    {
      name = "thunderbolt-xdomain-properties-response-validate";
      patch = ./patches/thunderbolt-xdomain-properties-response-validate.patch;
    }
    {
      name = "thunderbolt-xdomain-bridge-hardening";
      patch = ./patches/thunderbolt-xdomain-bridge-hardening.patch;
    }
    {
      name = "thunderbolt-xdomain-bridge-resync";
      patch = ./patches/thunderbolt-xdomain-bridge-resync.patch;
    }
  ];

  # Stable 7.0.x from nixpkgs (latest), patched. For hosts that need ZFS -
  # ZFS upstream currently caps at kernel 7.0, so the 7.1-rc1 variant of this
  # profile breaks the zfs-kernel build. The usb4-stream / CONFIGFS additions
  # are still picked up because they're applied as kernelPatches on top of
  # whatever the base release ships.
  linuxPackagesUsb4 = pkgs.linuxPackages_latest.extend (self: super: {
    kernel = super.kernel.override {
      kernelPatches = (super.kernel.kernelPatches or [ ]) ++ thunderboltKernelPatches ++ localThunderboltKernelPatches;
      structuredExtraConfig = with lib.kernel; {
        USB4_DEBUGFS_WRITE = yes;
      };
    };
  });
in
{
  boot.kernelPackages = lib.mkOverride 900 linuxPackagesUsb4;
  boot.extraModprobeConfig = ''
    options thunderbolt xdomain_lane_bonding=0 xdomain_debug=1 xdomain_route_properties=1
  '';
}
