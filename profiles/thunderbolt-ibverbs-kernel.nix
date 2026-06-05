{ pkgs
, lib
, inputs
, ...
}:
let
  thunderboltIbverbs = inputs.thunderbolt-ibverbs-kernel;
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
  linuxPackagesThunderbolt = pkgs.linuxPackages_latest.extend (self: super: {
    kernel = super.kernel.override {
      kernelPatches = (super.kernel.kernelPatches or [ ]) ++ thunderboltKernelPatches ++ localThunderboltKernelPatches;
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
    options thunderbolt xdomain_lane_bonding=0 xdomain_debug=1 xdomain_route_properties=1
  '';

  hardware.thunderbolt-ibverbs.enable = true;
}
