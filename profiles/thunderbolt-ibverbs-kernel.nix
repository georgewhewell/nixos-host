{ pkgs
, lib
, inputs
, ...
}:
let
  thunderboltIbverbs = inputs.thunderbolt-ibverbs-kernel;
  thunderboltIbverbsPackages =
    thunderboltIbverbs.packages.${pkgs.stdenv.hostPlatform.system};
  linuxPackagesThunderbolt =
    pkgs.linuxPackagesFor thunderboltIbverbsPackages.linux-thunderbolt;
in
{
  # The thunderbolt-ibverbs NixOS module is brought in by
  # `nix-strix-halo.nixosModules.default`, pinned via
  # `inputs.thunderbolt-ibverbs.follows = "thunderbolt-ibverbs-kernel"`
  # in the top-level flake. Re-importing it here causes an
  # already-declared error on `hardware.thunderbolt-ibverbs.enable`.

  boot.kernelPackages = lib.mkOverride 900 linuxPackagesThunderbolt;

  hardware.thunderbolt-ibverbs.enable = true;
}
