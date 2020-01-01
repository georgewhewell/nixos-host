{ stdenv, fetchFromGitHub }:

stdenv.mkDerivation rec {
  name = "armbian-firmware";

  src = fetchFromGitHub {
    owner = "armbian";
    repo = "firmware";
    rev = "1a4a517070a784dac0f9a42ce192fc92cd082c47";
    sha256 = "172g29sb61q80nf1b75wmpp490fyrzx87i5la5mkl7xq0bmp2s87";
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/lib/firmware
    cp -rv . $out/lib/firmware
  '';

  meta = {
    description = "friendlyarm firmware files for AP6212 ";
    maintainers = [ stdenv.lib.maintainers.georgewhewell ];
    /*platforms = [ stdenv.lib.platforms.all ];*/
  };

}
