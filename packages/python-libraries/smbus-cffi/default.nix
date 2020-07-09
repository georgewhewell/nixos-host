{ stdenv
, lib
, buildPythonPackage
, fetchPypi
, python
, libffi
, cffi
}:

buildPythonPackage rec {
  pname = "smbus-cffi";
  version = "0.5.1";

  src = fetchPypi {
    inherit pname version;
    sha256 = "1s5xsvd6i1z44dz5kz924vqzh6ybnn8323gncdl5h0gwmfm9ahgv";
  };

  buildInputs = [ libffi ];
  propagatedBuildInputs = [ cffi ];

}
