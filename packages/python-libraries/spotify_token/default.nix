{ stdenv
, lib
, buildPythonPackage
, fetchPypi
, python
, requests
, beautifulsoup4
, lxml
}:

buildPythonPackage rec {
  pname = "spotify_token";
  version = "1.0.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "1ckcyawws45nqihk1z8m0fr8r3414fxz609ln75xqkdcvsf50a4n";
  };

  postPatch = ''
    echo "" > requirements.txt
  '';

  propagatedBuildInputs = [ requests beautifulsoup4 lxml ];

  doCheck = false;

}
