{ stdenv
, lib
, buildPythonPackage
, fetchPypi
, python
}:

buildPythonPackage rec {
  pname = "python-periphery";
  version = "2.0.1";

  src = fetchPypi {
    inherit pname version;
    sha256 = "1v0qpv0i2kqhjvl6wvvvy29hazjdcym7nn14qzv4r5zq1zsdb92x";
  };


}
