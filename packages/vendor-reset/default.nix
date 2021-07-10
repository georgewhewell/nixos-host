{ stdenv, sources, kernel }:

stdenv.mkDerivation {
  name = "vendor-reset";

  src = sources.vendor-reset;

  makeFlags = [
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "INSTALL_MOD_PATH=${placeholder "out"}"
  ];

  meta = {
    platforms = stdenv.lib.platforms.linux;
  };
}
