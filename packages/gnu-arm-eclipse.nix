{ stdenv, fetchurl, mono, curl, makeWrapper }:

stdenv.mkDerivation rec {
  name = "jackett-${version}";
  version = "0.7.1296";

  src = fetchurl {
    url = "https://dl.espressif.com/dl/xtensa-esp32-elf-linux64-1.22.0-80-g6c4433a-5.2.0.tar.gz";
    sha256 = "14a94dddachh30gp23w8av39y0s7rm12sqvg2l522qd12f9zv2yw";
  };

  buildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/{bin,share/${name}}
    cp -r * $out/share/${name}

    makeWrapper "${mono}/bin/mono" $out/bin/Jackett \
      --add-flags "$out/share/${name}/JackettConsole.exe" \
      --prefix LD_LIBRARY_PATH ':' "${curl.out}/lib"
  '';

  meta = with stdenv.lib; {
    description = "API Support for your favorite torrent trackers.";
    homepage = https://github.com/Jackett/Jackett/;
    license = licenses.gpl2;
    maintainers = with maintainers; [ edwtjo ];
    platforms = platforms.all;
  };
}
