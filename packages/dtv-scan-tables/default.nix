{ stdenv, fetchgit }:

stdenv.mkDerivation {
  name = "dtv-scan-tables";
  version = "2019-09-25";

  src = fetchgit {
    url = "git://linuxtv.org/dtv-scan-tables.git";
    rev = "6d019038cd04e837d9dd58701202c15924c1c654";
    sha256 = "1iz45zzsvxiif8nr3b5hnvk8wwsixwqkc8ph0nn85dclqfzdc1sj";
  };

  buildPhase = ''
    mkdir -p $out/share/dvb
  '';

  installPhase = ''
    cp -rv * $out/share/dvb
  '';

}
