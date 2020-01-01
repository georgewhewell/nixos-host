{ config, lib, pkgs, usbBoot ? false }:

pkgs.stdenv.mkDerivation rec {
    version="master";
    name = "bl1-nanopi-m3-${version}";

    src = pkgs.fetchFromGitHub {
      owner = "rafaello7";
      repo = "bl1-nanopi-m3";
      rev = "f53c8d83b9d6057e39d6c5cf556a10d7a6d1f692";
      sha256 = "15qhv2s99lyjx92abhl7iq3v3s1468bjzfkxj0dh7xlh4wk6hmaj";
    };

    hardeningDisable = [ "all" ];

    postPatch = lib.optional usbBoot ''
      sed -i -e 's/0x03000000/0x00000000/g' src/startup_aarch64.S
    '';

    buildPhase = ''
      make CROSS_TOOL=${pkgs.stdenv.cc.targetPrefix} OBJCOPY=${pkgs.binutils}/bin/objcopy
    '';

    installPhase = ''
      cp out/bl1-nanopi.bin $out
    '';
}
 
