{ stdenv
, lib
, buildPythonPackage
, fetchFromGitHub
, fetchPypi
, python
, pytest
, btlewrap
}:

buildPythonPackage rec {
  pname = "miflora";
  version = "0.4";

  /*
  src = fetchFromGitHub {
    owner = "hechi";
    repo = "miflora";
    rev = "bumpversion-0.7";
    sha256 = "0gq6lmgkgixy6n9lcynqpb1imb7b3whnrl9iimv4v8c5cz7vrvay";
  };
*/  
  src = fetchFromGitHub {
    owner = "open-homeautomation";
    repo = "miflora";
    rev = "master";
    sha256 = "1kdjmmh04xyp9x65iqp4xs31nnlhi4bjqr394q1qzg1vvq2brxhg";
  };
  propagatedBuildInputs = [ btlewrap ];

  postPatch = ''
    sed -i '/install_requires/d' setup.py
    rm -rf test
  '';
  
  checkInputs = [ pytest ];
  doCheck = false;

}
