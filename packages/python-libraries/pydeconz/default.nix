{ stdenv
, buildPythonPackage
, fetchPypi
, aiohttp
}:

buildPythonPackage rec {
  pname = "pydeconz";
  version = "54";

  src = fetchPypi {
    inherit pname version;
    sha256 = "0fnq6ak99r9d6j1dmin2wx9cis5xkjp23jvgr1crzjiibk0b441h";
  };

  propagatedBuildInputs = [ aiohttp ];
  doCheck = false;

}
