{ pkgs, ... }:

with pkgs;

{
  si2168_02 = callPackage ./si2168-02.nix { };
  couchpotato = callPackage ./couchpotato.nix { };
  prometheus-snmp-exporter = callPackage ./snmp-exporter.nix { };
}
