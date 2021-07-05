{ stdenv, sources, kernel }:

stdenv.mkDerivation rec {
  name = "i2c-ch341-usb";
  version = "5.6.4.2_35491.20200318";

  src = sources.i2c-ch341-usb;

  prePatch = ''
   substituteInPlace ./Makefile --replace /lib/modules/ "${kernel.dev}/lib/modules/"
   substituteInPlace ./Makefile --replace '$(shell uname -r)' "${kernel.modDirVersion}"
   substituteInPlace ./Makefile --replace '/lib/modules/$(KVERSION)/build' "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
 '';

}
