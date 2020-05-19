{ stdenv
, lib
, buildPythonPackage
, fetchPypi
, python
}:

buildPythonPackage rec {
  pname = "OPi.GPIO";
  version = "0.4.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "0f79qksacfn9hg4bps8l00ly0k55ipfqfyq444dz5dyysg3rvq5a";
  };

  propagatedBuildInputs = [  ];

  doCheck = false;

}
