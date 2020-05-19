{ stdenv, fetchFromGitHub }:

stdenv.mkDerivation rec {
  name = "armbian-firmware";

  src = fetchFromGitHub {
    owner = "armbian";
    repo = "firmware";
    rev = "9258bc72597ee6a72a4001bf35c34299cea15af3";
    sha256 = "1f7hyp7bxp82q23nb8pdnd5fsyski96xsmhyq2d8vyy5n9ns0s4v";
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/lib/firmware
    cp -rv . $out/lib/firmware
  '';

  meta = {
    description = "armbian firmware files";
    maintainers = [ stdenv.lib.maintainers.georgewhewell ];
    /*platforms = [ stdenv.lib.platforms.all ];*/
  };

}
