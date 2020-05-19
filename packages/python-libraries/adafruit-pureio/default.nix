{ stdenv
, lib
, buildPythonPackage
, fetchPypi
, python
, setuptools_scm
}:

buildPythonPackage rec {
  pname = "Adafruit_PureIO";
  version = "1.1.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "0igx7k33jcbh6vcxh52m4dbk3ibswhj883rz1ldrsgyvrsi88cvz";
  };

  buildInputs = [ setuptools_scm ];
}
