{ stdenv, lib, fetchurl, zlib, ... }:

stdenv.mkDerivation rec {
  name = "xtensa-esp32-elf-${version}";
  version = "1.22.0-80-g6c4433a-5.2.0";

  src = fetchurl {
    url = "https://dl.espressif.com/dl/xtensa-esp32-elf-linux64-${version}.tar.gz";
    sha256 = "0mji8jq1dg198z8bl50i0hs3drdqa446kvf6xpjx9ha63lanrs9z";
  };

  phases = [ "unpackPhase" "installPhase" "fixupPhase" ];

  installPhase = ''
    mkdir -p $out
    cp -r * $out
  '';

  dontPatchELF = true;
  dontStrip = true;

  preFixup = ''
    find $out -type f | while read f; do
      patchelf $f > /dev/null 2>&1 || continue
      patchelf --set-interpreter $(cat ${stdenv.cc}/nix-support/dynamic-linker) "$f" || true
      patchelf --set-rpath ${lib.makeLibraryPath [ "$out" stdenv.cc.cc zlib ]} "$f" || true
    done
  '';

  meta = {
    description = "xtensa esp32 toolchain";
    platforms = [ "x86_64-linux" ];
  };
}
