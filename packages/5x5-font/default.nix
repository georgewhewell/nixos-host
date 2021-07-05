{ stdenv, fetchFromGitHub }:

stdenv.mkDerivation rec {
  pname = "5x5";
  version = "dirty";

  src = ./5x5;

  installPhase = ''
    install -D -m 444 * -t $out/share/fonts/ttf
  '';

}
