{
  buildPythonPackage
  ,tensorflowWithCuda
  ,numpy
  ,scipy
  ,fetchurl
  ,wheel
}:

buildPythonPackage {
  pname = "jaxlib";
  version = "?";

  src = fetchurl {
    /* inherit pname version; */
    url = "https://files.pythonhosted.org/packages/b4/4a/3c1a1dc6dd01d45f53fb9afd59a909e1c744bfc7d359309efad12451c7a1/jaxlib-0.1.65-cp38-none-manylinux2010_x86_64.whl";
    sha256 = "19hmkrrcpz4h2rcyqidan9im5qv9kr9j8h12sv5dif65ndwaq0hb";
  };

  nativeBuildInputs = [ wheel ];

  propagatedBuildInputs = [
    /* tensorflowWithCuda
    numpy
    scipy */
  ];

    preConfigure = ''
      unset SOURCE_DATE_EPOCH
      # Make sure that dist and the wheel file are writable.
      chmod u+rwx -R ./dist
      pushd dist
      # Unpack the wheel file.
      wheel unpack --dest unpacked ./*.whl
      
            # Pack the wheel file back up.
      wheel pack ./unpacked/tensorflow*
      popd
    '';

}
