{ stdenv, fetchFromGitHub, ... }:

stdenv.mkDerivation {
  name = "libreelec-fw-dvb";

  src = fetchFromGitHub {
    owner = "LibreElec";
    repo = "dvb-firmware";
    rev = "82f1b520e82fd4889ddb062fe5c7d40dcb773069";
    sha256 = "1lf8l8lqc6nr2wfrawld7mnyxffpvlw2lq86ahdvb6y41hzic2n6";
  };

  buildPhase = "";
  installPhase = ''
    mkdir -p $out/lib
    cp -rv firmware $out/lib/
  '';

  meta = with stdenv.lib; {
    license = stdenv.lib.licenses.unfreeRedistributableFirmware;
    maintainers = with maintainers; [ georgewhewell ];
    platforms = with platforms; linux;
  };
}
