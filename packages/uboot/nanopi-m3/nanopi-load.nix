{ stdenv, buildPackages, sources, libusb, pkgconfig }:

stdenv.mkDerivation rec {
  pname = "nanopi-load";
  version = sources.nanopi-load.rev;
  src = sources.nanopi-load;

  buildInputs = [ libusb  ];
  nativeBuildInputs = [ buildPackages.pkgconfig ];
  hardeningDisable = [ "all" ];

  preConfigure = ''
    substituteInPlace Makefile \
      --replace pkg-config $PKG_CONFIG

    substituteInPlace Makefile \
      --replace gcc $CC
  '';

  installPhase = ''
    mkdir -p $out/bin
    mv nanopi-load $out/bin/
  '';

}
