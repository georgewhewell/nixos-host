{ config, lib, pkgs, ... }:

{
  nixpkgs.config = {
    packageOverrides = pkgs: {
      inherit (pkgs.callPackages ../packages/default.nix { })
        si2168_02 couchpotato kubernetes_15 thin-provisioning-tools cni
        prometheus-snmp-exporter prometheus-ipmi-exporter;
    };
  };
}
