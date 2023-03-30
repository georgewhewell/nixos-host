{ stdenv
, cmake
, libmemifSource
}:

stdenv.mkDerivation {
  name = "libmemif";

  src = libmemifSource;

  patches = [ ./fix-cmakelists-libmemif.patch ];

  nativeBuildInputs = [ cmake ];
}
