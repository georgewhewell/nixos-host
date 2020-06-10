{ stdenv, sources, libusb, pkgconfig }:

stdenv.mkDerivation rec {
  pname = "nanopi-load";
  version = sources.nanopi-load.rev;
  src = sources.nanopi-load;

  nativeBuildInputs = [ libusb pkgconfig ];
  hardeningDisable = [ "all" ];

  installPhase = ''
    mkdir -p $out/bin
    mv nanopi-load $out/bin/
  '';

}
