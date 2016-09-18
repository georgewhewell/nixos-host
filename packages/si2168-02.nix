
{ stdenv, fetchurl }:

stdenv.mkDerivation rec {
  name = "si2168-02";
  version = "2015-12-04";

  # This repo is built by merging the latest versions of
  # http://git.kernel.org/cgit/linux/kernel/git/firmware/linux-firmware.git/
  # and
  # http://git.kernel.org/cgit/linux/kernel/git/iwlwifi/linux-firmware.git/
  # for any given date. This gives us up to date iwlwifi firmware as well as
  # the usual set of firmware. firmware/linux-firmware usually lags kernel releases
  # so iwlwifi cards will fail to load on newly released kernels.
  src = fetchurl {
    sha256 = "1497kh3a9pz8ijskihg54mgxlqgxpf1187f36anmdz9r1jdw3b8s";
    url = "https://git.tsar.su/grw/Si2168-fw/archive/master.tar.gz";
  };


  phases = ["unpackPhase" "installPhase"];

  installPhase = ''
    mkdir -p $out/lib/firmware
    cp *.fw $out/lib/firmware/
  '';

}

