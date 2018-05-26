{ nixpkgs ? <nixpkgs> }:

let

  pkgs = import nixpkgs { overlays = [
    (self: super: import modules/overlay.nix { inherit self super; })
  ]; };

  build = config:
    (import <nixpkgs/nixos/lib/eval-config.nix> {
      system = "x86_64-linux";
      modules = [ config ];
    }).config.system.build;

in {

  fuckup = (build ./fuckup.nix).toplevel;
  router = (build ./router.nix).toplevel;
  nixhost = (build ./nixhost.nix).toplevel;
  yoga = (build ./yoga.nix).toplevel;

  installer = (build ./installer-x86.nix).isoImage;

}
