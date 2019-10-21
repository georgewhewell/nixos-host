{ stdenv
, buildPythonPackage
, fetchPypi
, pkg-config
, gtk2
}:

buildPythonPackage rec {
  pname = "bluepy";
  version = "1.3.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "1v0wjy1rz0rbwghr1z3xhdm06lqn9iig6vr5j2wmymh3w6pysw9a";
  };

  buildInputs = [ gtk2 ];
  nativeBuildInputs = [ pkg-config ];

  doCheck = false;

  meta = with stdenv.lib; {
    description = "Python interface to Bluetooth LE on Linux ";
    homepage = "https://github.com/IanHarvey/bluepy";
    maintainers = with maintainers; [ georgewhewell ];
    license = licenses.gpl2;
  };

}
