{ config
, lib
, ...
}:
let
  inherit (config.nixpkgs) localSystem;
  selectedPlatform = lib.systems.elaborate "aarch64-linux";
  isCross = localSystem.system != selectedPlatform.system;
in
lib.mkMerge [
  {
    boot.supportedFilesystems = lib.mkForce [ "vfat" ];

    nixpkgs.overlays = [
      (final: super: {
        # Workaround for modules expected by NixOS not being built more often than not.
        # TODO Do we still need this?
        makeModulesClosure = x: super.makeModulesClosure (x // { allowMissing = true; });
      })
    ];
  }
  (lib.mkIf isCross {
    # Some filesystems (e.g. zfs) have some trouble with cross (or with BSP kernels?) here.

    nixpkgs.crossSystem = builtins.trace ''
      Building with a crossSystem?: ${selectedPlatform.system} != ${localSystem.system} → ${
        if isCross
        then "we are"
        else "we're not"
      }.
             crossSystem: config: ${selectedPlatform.config}''
      selectedPlatform;
  })
]
