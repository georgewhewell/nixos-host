{ nixpkgs ? <nixpkgs> }:

let
  crossFixes = (import ./machines/common-cross.nix);
  pkgs = (import nixpkgs { overlays = [
    (import modules/overlay.nix)
  ]; });
  lib = pkgs.lib;
  build = system: config:
    (import <nixpkgs/nixos/lib/eval-config.nix> {
      inherit system;
      modules = [ config ];
    }).config.system.build;
  buildCross = crossSystem: config:
    let crossBit = { config, lib, ...}: {
      nixpkgs.crossSystem = lib.systems.elaborate {
        config = crossSystem;
      };
    };
    in (import <nixpkgs/nixos/lib/eval-config.nix> {
      modules = [ config crossBit crossFixes ];
    }).config.system.build;
  armMachines = (import ./machines/armv7l { inherit lib; });
  aarch64Machines = (import ./machines/aarch64 { inherit lib; });
in {

  inherit pkgs;

  fuckup = (build "x86_64-linux" ./fuckup.nix).toplevel;
  router = (build "x86_64-linux" ./router.nix).toplevel;
  nixhost = (build "x86_64-linux" ./nixhost.nix);
  yoga = (build "x86_64-linux" ./yoga.nix).toplevel;

  installer = (build "x86_64-linux"  ./installer-x86.nix).isoImage;

  armv7l = pkgs.lib.mapAttrs (name: configuration:
    (build "armv7l-linux" configuration).sdImage
  ) armMachines;

  armv7lCross = pkgs.lib.mapAttrs(name: configuration:
    (buildCross "armv7l-unknown-linux-gnueabihf" configuration)
  ) armMachines;

  aarch64 = pkgs.lib.mapAttrs (name: configuration:
    (build "aarch64-linux" configuration).sdImage
  ) aarch64Machines;

  aarch64Cross = pkgs.lib.mapAttrs(name: configuration:
    (buildCross "aarch64-unknown-linux-gnu" configuration)
  ) aarch64Machines;

}
