{ stdenv
, buildPackages
, buildPythonPackage
, fetchPypi
, pkg-config
, glib
}:

buildPythonPackage rec {
  pname = "bluepy";
  version = "1.3.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "1v0wjy1rz0rbwghr1z3xhdm06lqn9iig6vr5j2wmymh3w6pysw9a";
  };

  preConfigure = ''
    substituteInPlace bluepy/Makefile \
      --replace "pkg-config" "$PKG_CONFIG"
  '';

  buildInputs = [ glib ];
  depsBuildBuild = [ buildPackages.stdenv.cc buildPackages.pkg-config ];

  # tests try to access hardware
  checkPhase = ''
    $out/bin/blescan --help > /dev/null
    $out/bin/sensortag --help > /dev/null
    $out/bin/thingy52 --help > /dev/null
  '';

  pythonImportsCheck = [ "bluepy" ];

  meta = with stdenv.lib; {
    description = "Python interface to Bluetooth LE on Linux";
    homepage = "https://github.com/IanHarvey/bluepy";
    maintainers = with maintainers; [ georgewhewell ];
    license = licenses.gpl2;
  };

}
