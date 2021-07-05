{ stdenv
, lib
, buildPythonPackage
, fetchPypi
, python
}:

buildPythonPackage rec {
  pname = "numpyro";
  version = "0.6.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "18r4byd78sv2k5r6rnrxnbw5j6kmiqpsvz64s5ky8lwlvs27dllp";
  };


}
