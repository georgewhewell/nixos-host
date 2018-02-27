{stdenv, fetchFromGitHub}:

stdenv.mkDerivation rec {
  name = "micro-ecc";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "kmackay";
    repo = "micro-ecc";
    rev = "v${version}";
    sha256 = "005qd76kk72w8kg6pr0r07d3wym5siazdwm79dypjp6073869szl";
  };

  enableParallelBuilding = true;
  installPhase = ''
    mkdir $out
    cp -rv * $out
  '';

  meta = with stdenv.lib; {
    description = "ECDH and ECDSA for 8-bit, 32-bit, and 64-bit processors.";
    platforms = platforms.all;
  };
}
