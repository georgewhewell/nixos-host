{ config, lib, pkgs, ... }:

{
  nixpkgs.config = {
    packageOverrides = pkgs: {
      inherit (pkgs.callPackages ../packages/default.nix { })
        si2168_02 couchpotato prometheus-snmp-exporter;
    };
  };
}
