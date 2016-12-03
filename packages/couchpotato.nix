{ stdenv, fetchgit }:

stdenv.mkDerivation rec {
  name = "couchpotato";
  version = "master";

  src = fetchgit {
    sha256 = "1khx6q9pl3pl0hwfiq8f3bd711hdwrbq2r2yk5hpbdzx2i2sa6z8";
    rev = "405779047035723bd015fdd51b19379884f53b36";
    url = "https://github.com/CouchPotato/CouchPotatoServer.git";
  };

  phases = ["unpackPhase" "installPhase"];

  installPhase = ''
    mkdir -p $out/
    mv * $out/
  '';

}
