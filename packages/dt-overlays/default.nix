{ pkgs, stdenv, config, ... }:

stdenv.mkDerivation rec {
  name = "dt-overlays";
  version = "0.1";
  src = ./overlays;
  installPhase = ''
    cp -r . $out
  '';
}
