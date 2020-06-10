{ stdenv, sources }:

stdenv.mkDerivation rec {
  name = "meson-firmware";

  src = sources.meson-firmware;

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/lib/firmware
    cp -rv . $out/lib/firmware
  '';
}
