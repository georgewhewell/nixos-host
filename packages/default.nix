{ pkgs ? import <nixpkgs> { }, ... }:

with pkgs;

rec {
  si2168_02 = callPackage ./si2168-02.nix { };
  BCM20702A1 = callPackage ./BCM20702A1.nix { };
  couchpotato = callPackage ./couchpotato.nix { };
  jackett = callPackage ./jackett.nix { };
  kubernetes_15 = callPackage ./kubernetes.nix { };
  radarr = callPackage ./radarr.nix { };
  headphones = callPackage ./headphones.nix { };
  thin-provisioning-tools = callPackage ./thin-provisioning-tools.nix { };
  clover = callPackage ./clover { };
  cni = callPackage ./cni.nix { };
  prometheus-snmp-exporter = callPackage ./snmp-exporter.nix { };
  prometheus-ipmi-exporter = callPackage ./ipmi-exporter.nix { };
  esp-open-sdk = callPackage ./esp-open-sdk.nix { };
  gonbdserver = callPackage ./gonbdserver { };
  xtensa-esp32-elf = callPackage ./xtensa-esp32-elf { };
  micro-ecc = callPackage ./micro-ecc { };
  esp-idf = callPackage ./esp-idf { inherit micro-ecc; };
  als-yoga = callPackage ./als-yoga { inherit (python.pkgs) buildPythonApplication; };
  
}
