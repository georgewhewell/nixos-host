{ stdenv
, lib
, buildPythonPackage
, fetchPypi
, python
, luma-core
}:

buildPythonPackage rec {
  pname = "luma.oled";
  version = "3.4.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "0llmi0iji462qwdw0ff4kxlxa00zm9wasm4c3ajmdw72wwsvb8if";
  };

  propagatedBuildInputs = [ luma-core ];

  doCheck = false;

}
