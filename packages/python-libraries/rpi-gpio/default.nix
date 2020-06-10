{ stdenv
, lib
, buildPythonPackage
, fetchPypi
, python
}:

buildPythonPackage rec {
  pname = "RPi.GPIO";
  version = "0.7.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "0gvxp0nfm2ph89f2j2zjv9vl10m0hy0w2rpn617pcrjl41nbq93l";
  };

  propagatedBuildInputs = [ ];

  doCheck = false;

}
