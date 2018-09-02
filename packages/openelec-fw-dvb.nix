{ stdenv, fetchFromGitHub, ... }:

stdenv.mkDerivation {
  name = "openelec-fw-dvb";

  src = fetchFromGitHub {
    owner = "OpenELEC";
    repo = "dvb-firmware";
    rev = "3fef04a4a4bfeba88ae3b20aff9d3a1fabf1c159";
    sha256 = "04lv3hv22r65ficrlq637jfyp8rbz9cjazvrsnv7z2q4cgz7gvbd";
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
