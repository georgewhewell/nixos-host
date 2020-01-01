{ stdenv, fetchFromGitHub }:

stdenv.mkDerivation rec {
  name = "meson-firmware";

  src = fetchFromGitHub {
    owner = "LibreELEC";
    repo = "meson-firmware";
    rev = "edd24b481293b93814494508cd4952b67f15acb3";
    sha256 = "0a0v9pfllkrx2fp3nlmhf3ypid00879bfhkgqd0pvn8rqkbzs873";
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/lib/firmware
    cp -rv . $out/lib/firmware
  '';
}
