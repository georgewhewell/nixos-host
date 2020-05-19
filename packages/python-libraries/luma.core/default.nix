{ stdenv
, lib
, buildPythonPackage
, fetchPypi
, python
, smbus2
, spidev
, pillow
, pyftdi
, rpi-gpio
, opi-gpio
}:

buildPythonPackage rec {
  pname = "luma.core";
  version = "1.14.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "05a25qzcssprmray11hyihiiasjxjm3n7dzilnwsnyf210gr008m";
  };

  propagatedBuildInputs = [ pillow pyftdi rpi-gpio smbus2 spidev opi-gpio ];

  doCheck = false;

}
