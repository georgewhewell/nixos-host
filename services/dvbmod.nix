{ options, config, lib, pkgs, stdenv, fetchurl, ... }:
let version = "1.0"; in
stdenv.mkDerivation {
  name = "dvb-demod-si2168";

  src = fetchurl {
    url = "http://palosaari.fi/linux/v4l-dvb/firmware/Si2168/Si2168-B40/4.0.4/dvb-demod-si2168-b40-01.fw";
    sha256 = "c6818c11c18cc030d55ff83f64b2bad8feef485e7742f84f94a61d811a6258bd";
  };

  phases = [ "installPhase" ];

  installPhase = ''
    mkdir -p $out/lib/firmware
    for fw in \
      dvb-demod-si2168-b40-01.fw \
      dvb-demod-si2168-b40-01.fw \
      dvb-demod-si2168-b40-01.fw
    do
      cp -f $fw $out/lib/firmware/$fw
    done
  '';

  meta = with stdenv.lib; {
    description = "Firmware for Intel 2200BG cards";
    homepage = http://ipw2200.sourceforge.net/firmware.php;
    license = stdenv.lib.licenses.unfreeRedistributableFirmware;
    maintainers = with maintainers; [ lukasepple ];
    platforms = with platforms; linux;
  };
}
