{ pkgs, ... }:

with pkgs;

{
  si2168_02 = callPackage ./si2168-02.nix { };
}
