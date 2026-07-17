{ pkgs
, lib
, inputs
, ...
}:
let
  thunderboltIbverbs = inputs.thunderbolt-ibverbs-kernel;
  system = pkgs.stdenv.hostPlatform.system;
  thunderboltPackages = thunderboltIbverbs.packages.${system};
  linuxPackagesThunderbolt =
    (pkgs.linuxPackagesFor thunderboltPackages.linux-thunderbolt).extend (self: super: {
      ryzen-smu = super.ryzen-smu.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ lib.optionals
          (lib.versionAtLeast super.kernel.version "7.2")
          [ ./patches/ryzen-smu-linux-7.2-cpuid-header.patch ];
      });
    });
in
{
  # The thunderbolt-ibverbs NixOS module is brought in by
  # `nix-strix-halo.nixosModules.default`, pinned via
  # `inputs.thunderbolt-ibverbs.follows = "thunderbolt-ibverbs-kernel"`
  # in the top-level flake. Re-importing it here causes an
  # already-declared error on `hardware.thunderbolt-ibverbs.enable`.

  boot.kernelPackages = lib.mkForce linuxPackagesThunderbolt;
  boot.extraModprobeConfig = ''
    options thunderbolt xdomain=1
    options thunderbolt_net e2e=0 tx_e2e=0
  '';

  hardware.thunderbolt-ibverbs.enable = true;
}
