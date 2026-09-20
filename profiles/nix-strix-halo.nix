{ inputs, lib, ... }:
{
  imports = [
    inputs.nix-strix-halo.inputs.thunderbolt-ibverbs.nixosModules.default
  ];

  # Keep Halo packages on its supported architectures. Nixpkgs also applies
  # overlays to compatibility package sets such as pkgsi686Linux, while Halo
  # and its Thunderbolt input do not export i686 packages.
  nixpkgs.overlays = [
    (final: prev:
      lib.optionalAttrs
        (builtins.hasAttr prev.stdenv.hostPlatform.system inputs.nix-strix-halo.packages)
        # Keep rdma-core-usb4 available to Halo applications without replacing
        # the fleet library. The global alias rebuilds libpcap, systemd,
        # PipeWire and desktop applications for the disabled USB4 transport.
        (builtins.removeAttrs
          (inputs.nix-strix-halo.overlays.default final prev)
          [ "rdma-core" ]))
  ];
}
