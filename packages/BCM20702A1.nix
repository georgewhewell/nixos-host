{ stdenv, fetchurl }:

stdenv.mkDerivation rec {
  name = "BCM20702A1";
  #name = "brcm/BCM20702A1-0b05-17cb.hcd";
  version = "2015-12-04";

  src = fetchurl {
    sha256 = "1497kh3a9pz8ijskihg54mgxlqgxpf1187f36anmdz9r1jdw3b8s";
    url = "http://dl.dropbox.com/u/25169171/BCM20702A0_001.001.024.0156.0204.hex";
  };


  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/lib/firmware
    cp *.fw $out/lib/firmware/
  '';

}
