{ stdenv, lib, fetchurl, fetchgit, micro-ecc, esptool, ncurses, flex, bison, gperf, ... }:

stdenv.mkDerivation rec {
  name = "esp-idf-${version}";
  version = "v3.0-rc1";

/*
  src = fetchurl {
    url = "https://github.com/espressif/esp-idf/archive/${version}.tar.gz";
    sha256 = "0v51wcgr6xx97l6bklh2c7m1za42jxhayv94dpjdc43p8jlksbvr";
  }; */

  src = fetchgit {
    url = "https://github.com/espressif/esp-idf.git";
    rev = "3ede9f011b50999b0560683f9419538c066dd09e";
    sha256 = "0c92pp4rgxyvz11dwz14q0sgdzq64xqmzr7vpbpnlq5alasjymrz";
    fetchSubmodules = true;
  };

  NIX_LDFLAGS = "-lncurses" ;
  propagatedBuildInputs = [ ncurses flex bison gperf ];

  postPatch = ''
    substituteInPlace tools/kconfig/Makefile \
      --replace "LDFLAGS :=" "LDFLAGS := -lncurses"
  '';

  buildPhase = ''
    (cd tools/kconfig && make conf mconf)
  '';

  installPhase = ''
    mkdir -p $out
    cp -r * $out
    env
    cp -rv ${micro-ecc}/uECC* $out/components/bootloader_support/src/
    rm -rf $out/components/esptool_py/esptool
    ln -fs ${esptool}/bin $out/components/esptool_py/esptool
  '';

  dontPatchELF = true;
  dontStrip = true;

  preFixup = ''
    find $out -type f | while read f; do
      patchelf $f > /dev/null 2>&1 || continue
      patchelf --set-interpreter $(cat ${stdenv.cc}/nix-support/dynamic-linker) "$f" || true
      patchelf --set-rpath ${lib.makeLibraryPath [ "$out" stdenv.cc.cc ]} "$f" || true
    done
  '';

  meta = {
    description = "esp idf";
    platforms = [ "x86_64-linux" ];
  };
}
