{ stdenv, binutils, openssl, sources }:

stdenv.mkDerivation rec {
    version="0.1";
    name = "meson-tools-${version}";

    src = sources.meson-tools;

    hardeningDisable = [ "all" ];
    nativeBuildInputs = [ binutils openssl ];

    installPhase = ''
      mkdir -p $out/bin
      cp amlinfo amlbootsig unamlbootsig $out/bin/
    '';

    meta = {
      description = "meson-tools";
      maintainers = [ stdenv.lib.maintainers.georgewhewell ];
    };

}
