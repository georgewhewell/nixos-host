{ stdenv, fetchgit }:

stdenv.mkDerivation rec {
  name = "couchpotato";
  version = "master";

  src = fetchgit {
    sha256 = "0f899j6wc7ip5m8lyhwixhpjiw6gmswc62za636f8kkiylsshrxj";
    rev = "b538f9a08db9a0be1af2f298727834edeafa322e";
    url = "https://github.com/CouchPotato/CouchPotatoServer.git";
  };

  phases = ["unpackPhase" "installPhase"];

  installPhase = ''
    mkdir -p $out/
    mv * $out/
  '';

}
