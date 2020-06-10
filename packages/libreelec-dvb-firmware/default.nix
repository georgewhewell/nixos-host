{ stdenv, sources }:

stdenv.mkDerivation {
  name = "libreelec-fw-dvb";
  
  version = sources.dvb-firmware.rev;
  src = sources.dvb-firmware;

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
