{
  stdenv, fetchgit,
  autoconf, automake, libtool,
  unrar, gperf,
  flex, bison,
  texinfo, ncurses,
  expat,
  python27Packages,
  wget,
  help2man,
  which, file, unzip, git
}:

stdenv.mkDerivation rec {
  name = "esp-open-sdk";

  src = fetchgit {
    url = "https://github.com/pfalcon/esp-open-sdk.git";
    rev = "350c0e91744e3e88ea4b91a9261cfed223093db6";
    sha256 = "0fwdr13nlqwpkm5824k9s4ik7fl0gxk9qcchgnfr2v99xx9jgjld";
    deepClone = true;
  };

  buildInputs = [
    autoconf
    automake
    libtool

    unrar
    gperf

    flex
    bison

    python27Packages.python

    texinfo
    ncurses

    expat

    wget
    help2man
    which
    file
    unzip
    git
  ];

  SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";

  hardeningDisable = [ "format" ];

  preConfigure = ''
    sed -i "s:/bin/bash:${stdenv.shell}:" Makefile

    # The lx106 configure script doesn't find the correct gcc, so we override it.
    sed -i 's:^CFLAGS:CC=$(readlink -f ../xtensa-lx106-elf/bin/xtensa-lx106-elf-gcc)\nCFLAGS:' lx106-hal/configure.ac
  '';

  buildPhase = ''
    make
  '';

  installPhase = ''
    mkdir -p $out/opt/esp-open-sdk

    cp -r xtensa-lx106-elf $out/opt/esp-open-sdk

    cp -r ESP8266_NONOS_SDK_* $out/opt/esp-open-sdk

    # I have esptool packaged separately, I don't want it here.
    rm $out/opt/esp-open-sdk/xtensa-lx106-elf/bin/esptool.py

    ln -s $out/opt/esp-open-sdk/xtensa-lx106-elf/bin $out/bin
  '';
}
