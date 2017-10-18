{ config, lib, pkgs, ... }:

{
  nixpkgs.config = let
    webscreensaver = pkgs.stdenv.mkDerivation {
      name = "webscreensaver";
      version = "0.1";
      src = pkgs.fetchFromGithub {
        owner = "lmartinking";
        repo = "webscreensaver";
        rev = "05a736c00fb66d902269d492d1a07febb7c4ed95";
        sha256 = "0wq8lrial1khc0kv34g2n7wbl9bf9m3vfk29d51g6r0hg3vzp49l";
      };
      installPhase = ''
        mkdir -p $out/bin
        cp webscreensaver $out/bin/webscreensaver
      '';

    };
    in {
    packageOverrides = pkgs: {
      inherit (pkgs.callPackages ../packages/default.nix { })
        si2168_02 couchpotato kubernetes_15 thin-provisioning-tools cni BCM20702A1
        prometheus-snmp-exporter prometheus-ipmi-exporter jackett radarr headphones webscreensaver;
    };
  };
}
