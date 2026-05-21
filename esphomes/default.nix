{pkgs ? let
  system = let
    v = builtins.getEnv "NIX_SYSTEM";
  in
    if v != "" then v else builtins.currentSystem;
  ref = let
    v = builtins.getEnv "ESPHOME_NIX_NIXPKGS";
  in
    if v != "" then v else "nixpkgs";
in
  (builtins.getFlake ref).legacyPackages.${system}}:
import ./lib.nix {inherit pkgs;}
