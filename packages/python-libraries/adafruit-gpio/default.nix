{ stdenv
, lib
, buildPythonPackage
, fetchPypi
, python
, adafruit-pureio
, spidev
}:

buildPythonPackage rec {
  pname = "Adafruit_GPIO";
  version = "1.0.3";

  src = fetchPypi {
    inherit pname version;
    sha256 = "1l6wlba5d5qhq40l3m8gdnscsp3gqcp8y7mwyfl1rib6r295ninn";
  };

  propagatedBuildInputs = [ adafruit-pureio spidev ];

  doCheck = false;

}
