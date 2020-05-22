{
stdenv
, fetchurl
}:

stdenv.mkDerivation rec {
  pname = "libdvbcsa";
  version = "1.1.0";

  src = fetchurl {
    url = "https://download.videolan.org/pub/videolan/libdvbcsa/${version}/libdvbcsa-${version}.tar.gz";
    sha256 = "0va57ypldl2l4yda2srv7sg7qiqajqqkbzin27xisr5jrpsqmdsd";
  };

}
