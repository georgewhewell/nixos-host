{ pkgs ? import <nixpkgs> { overlays = [ (import ./../../modules/overlay.nix) ]; } }:

pkgs.callPackage ./default.nix { }
