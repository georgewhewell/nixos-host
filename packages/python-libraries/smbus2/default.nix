{ stdenv
, lib
, buildPythonPackage
, fetchPypi
, python
}:

buildPythonPackage rec {
  pname = "smbus2";
  version = "0.3.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "1d1848i0mqm042dl42wcj72f2hhrhi8jgv5k6vl1y2sdpvp6c3i1";
  };


}
