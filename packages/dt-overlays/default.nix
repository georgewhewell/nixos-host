{ pkgs, stdenv, config, ... }:

stdenv.mkDerivation rec {
  name = "dt-overlays";
  version = "0.1";
  src = ./overlays;

  nativeBuildInputs = with pkgs; [ dtc ];

  installPhase = ''
    mkdir $out
    for f in *.dts; do
      dtc -I dts $f -O dtb -@ -o $out/$(basename $f).dtbo
    done
  '';
}
