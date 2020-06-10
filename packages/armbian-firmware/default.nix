{ stdenv, sources }:

stdenv.mkDerivation rec {
  name = "armbian-firmware";

  src = sources.armbian_firmware;

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/lib/firmware
    cp -rv . $out/lib/firmware
  '';

  meta = {
    description = "armbian firmware files";
    maintainers = [ stdenv.lib.maintainers.georgewhewell ];
  };

}
