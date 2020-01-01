{ config, lib, pkgs, ... }:

pkgs.stdenv.mkDerivation rec {
  version="master";
  name = "nanopi-load-${version}";

  src = pkgs.fetchFromGitHub {
    owner = "rafaello7";
    repo = "nanopi-load";
    rev = "001d2e36ff91e130c0ace5e152d224b05681b6e3";
    sha256 = "187hgsa5rrw1f8q2zfhfr31p8didh5sgj051ddl1lq617wgj7798";
  };

  nativeBuildInputs = [ pkgs.libusb pkgs.pkgconfig pkgs.gcc ];
  hardeningDisable = [ "all" ];

  installPhase = ''
     mkdir -p $out/bin
     mv nanopi-load $out/bin/
  '';

 }

