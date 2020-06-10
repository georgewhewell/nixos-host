{ sources, lib, pkgs, usbBoot ? false }:

pkgs.stdenv.mkDerivation rec {
  pname = "bl1-nanopi-m3";

  src = sources.bl1-nanopi-m3;
  version = sources.bl1-nanopi-m3.rev;

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
