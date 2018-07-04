{ stdenv, fetchFromGitHub, glib, libusb, qmake4Hook }: #, makeWrapper, qtwebkit, qtxmlpatterns, qttranslations, lsb-release }:

stdenv.mkDerivation rec {
  name = "gemini-flashtool";

  src = fetchFromGitHub {
    owner = "dguidipc";
    repo  = "SP-Flash-Tool-src";
    rev   = "a12e2b1b1ee7b46fc25d0fc7de56e4d519213227";
    sha256 = "067bqv4703znrdy5in6ni16hr4rvsmbwx1bxk02xc0chjpfbzkbi";
  };

  nativeBuildInputs = [ qmake4Hook ];
 /*
  fixupPhase = let
      libPath = stdenv.lib.makeLibraryPath [ glib libusb ];
    in ''
      find $out/bin -type f | while read f; do
        patchelf $f > /dev/null 2>&1 || continue
        patchelf --set-interpreter $(cat ${pkgs.pkgsi686Linux.stdenv.cc}/nix-support/dynamic-linker) "$f" || true
        patchelf --set-rpath ${libPath} "$f" || true
      done
  '';
*/
  installPhase = ''
    mkdir -p $out/{bin,lib}
    cp flash_tool $out/bin/
    cp -rv Lib/*.so $out/lib/
    cp -rv Lib/QtLinux/lib/*.so.* $out/lib/
  '';

  meta = {
    description = "rockchip firmware and binaries";
    maintainers = [ stdenv.lib.maintainers.georgewhewell ];
    #platforms = [ "i686-linux" ];
  };

}
