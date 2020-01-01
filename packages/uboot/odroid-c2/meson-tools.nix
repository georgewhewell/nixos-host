{ stdenv, binutils, openssl, fetchFromGitHub }:

stdenv.mkDerivation rec {
    version="0.1";
    name = "meson-tools-${version}";

    src = fetchFromGitHub {
      owner = "afaerber";
      repo = "meson-tools";
      rev = "v${version}";
      sha256 = "1bvshfa9pa012yzdwapi3nalpgcwmfq7d3n3w3mlr357a6kq64qk";
    };

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
