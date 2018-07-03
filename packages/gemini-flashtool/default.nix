{ pkgs }:

with pkgs.pkgsi686Linux; stdenv.mkDerivation rec {
  name = "rkbin";

  src = fetchurl {
    url = "http://support.planetcom.co.uk/download/FlashToolLinux.tgz";
    sha256 = "010ysrdzf1nww0ia264nb89f76m8q2rh7n07x9vps506zgx346sn";
  };

  installPhase = ''
    cp -r . $out
  '';

  fixupPhase = let
      libPath = stdenv.lib.makeLibraryPath [ glib libusb ];
    in ''
      find $out/bin -type f | while read f; do
        patchelf $f > /dev/null 2>&1 || continue
        patchelf --set-interpreter $(cat ${pkgs.pkgsi686Linux.stdenv.cc}/nix-support/dynamic-linker) "$f" || true
        patchelf --set-rpath ${libPath} "$f" || true
      done
  '';

  meta = {
    description = "rockchip firmware and binaries";
    maintainers = [ stdenv.lib.maintainers.georgewhewell ];
    platforms = [ "i686-linux" ];
  };

}
