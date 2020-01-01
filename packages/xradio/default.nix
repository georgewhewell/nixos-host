{ stdenv, fetchFromGitHub, kernel }:

let
 version = "2019-06-17";
in
stdenv.mkDerivation {
  name = "xradio-${version}-${kernel.version}";

  src = fetchFromGitHub {
    owner = "fifteenhex";
    repo = "xradio";
    rev = "aa01ba77b9360dd734b50f5b937960a50c5a0825";
    sha256 = "06h0yjz831i62jphkdxjd6jqplc7g5m7xp8jy5xp1rnmlyj4w9xf";
  };

  hardeningDisable = [ "pic" ];

  nativeBuildInputs = kernel.moduleBuildDependencies;

  patches = [ ];

  #makeFlags = ["-C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=." "modules"];
  buildPhase = ''
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$(pwd) modules
  '';

  /*
  installPhase = ''
    binDir="$out/lib/modules/${kernel.modDirVersion}/kernel/net/wireless/"
    docDir="$out/share/doc/broadcom-sta/"
    mkdir -p "$binDir" "$docDir"
    cp wl.ko "$binDir"
    cp lib/LICENSE.txt "$docDir"
  '';
  */
  meta = {
    description = "Port Allwinner xradio driver to mainline Linux";
    # homepage = http://www.broadcom.com/support/802.11/linux_sta.php;
    # license = stdenv.lib.licenses.unfreeRedistributable;
    maintainers = with stdenv.lib.maintainers; [ georgewhewell ];
    platforms = stdenv.lib.platforms.linux;
  };
}
