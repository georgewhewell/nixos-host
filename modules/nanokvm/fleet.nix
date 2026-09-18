# Explicit fleet composition factory (not an automatically imported module).
# The upstream flake supplies hardware, toolchains,
# kernels and ROM upload; SD roots, NFS/NBD and host networking belong here.
{ inputs }:
let
  nanokvm = inputs.nanokvm;
  inherit (nanokvm.inputs.nixpkgs) lib;
  catalog = import ./lib/catalog.nix { inherit lib nanokvm; };
  mkBoard = entry: {
    imports = [
      (nanokvm + "/boards/${entry.boardName}.nix")
      (nanokvm + "/profiles/kernel/${entry.kernel}.nix")
      (import (./profiles + "/${entry.profile}.nix") { inherit nanokvm; })
      (nanokvm + "/modules/sg2002-watchdog-keeper.nix")
      nanokvm.nixosModules.default
      inputs.impermanence.nixosModules.impermanence
      inputs.disko.nixosModules.disko
    ] ++ (entry.mixins or [ ]) ++ (entry.modules or [ ]);
    _module.args = {
      rootAuthorizedKeys = [ ];
      rootWpaConf = null;
      selfOverlay = nanokvm.overlays.default;
      allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "nanokvm-factory-runtime" "sg2002-coda980-firmware"
        "sg2002-c906l-firmware" "sophgo-host-tools"
      ];
    };
    nixpkgs.overlays = [ (import ./overlay.nix) ];
  };
in {
  boards = lib.foldl' (acc: entry:
    lib.recursiveUpdate acc (lib.setAttrByPath entry.path (mkBoard entry))
  ) { } catalog;
  artifacts = pkgs: import ./lib/artifacts.nix {
    inherit lib nanokvm;
    hostShellPrelude = import ./lib/host-prelude.nix
      (import (nanokvm + "/lib/protocol.nix"));
  } (pkgs.extend (import ./overlay.nix));
}
