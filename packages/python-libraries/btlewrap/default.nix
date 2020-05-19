{ stdenv
, lib
, buildPythonPackage
, fetchPypi
, python
, pytest
, bluepy
, typing
}:

buildPythonPackage rec {
  pname = "btlewrap";
  version = "0.0.9";

  src = fetchPypi {
    inherit pname version;
    sha256 = "0d1qcq25wbk4gjsvhjanp6qssfbgjglj4v2cnldp8p0as05g47i1";
  };

  postPatch = ''
    sed -i '/install_requires/d' setup.py
  '';

  checkInputs = [ pytest ];
  propagatedBuildInputs = [ bluepy ];

  doCheck = false;

}
