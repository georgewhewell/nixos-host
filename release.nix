{ nixpkgs ? <nixpkgs> }:

let

  pkgs = import nixpkgs { overlays = [
    ./modules/overlay.nix
  ]; };

  build = config:
    (import <nixpkgs/nixos/lib/eval-config.nix> {
      system = "x86_64-linux";
      modules = [ config ];
    }).config.system.build.toplevel;

in {

  fuckup = build ./fuckup.nix;
  router = build ./router.nix;
  nixhost = build ./nixhost.nix;
  yoga = build ./yoga.nix;

}
