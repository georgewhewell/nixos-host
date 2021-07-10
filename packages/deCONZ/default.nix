{ config, pkgs, stdenv, buildFHSUserEnv, fetchurl, dpkg, qt5, sqlite, hicolor_icon_theme, libcap, libpng, ... }:
let
  version = "2.05.72";

  name = "deconz-${version}";
in
rec {
  deCONZ-deb = stdenv.mkDerivation {
    inherit name;
    dpkg = dpkg;
    src = fetchurl {
      url = "https://deconz.dresden-elektronik.de/ubuntu/beta/${name}-qt5.deb";
      sha256 = "1ma5qdpccapnvm6wh7h2isggxx1lkkjlaymrf05d1n3dsdr7dnpy";
    };

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    buildInputs = [ dpkg qt5.qtbase qt5.qtserialport qt5.qtwebsockets sqlite hicolor_icon_theme libcap libpng qt5.wrapQtAppsHook ];

    unpackPhase = "dpkg-deb -x $src .";
    installPhase = ''
      cp -r usr/* .
      cp -r share/deCONZ/plugins/* lib/
      cp -r . $out
    '';

  };
  deCONZ = buildFHSUserEnv {
    name = "deCONZ";
    targetPkgs = pkgs: [
      deCONZ-deb
    ];
    multiPkgs = pkgs: [
      dpkg
      qt5.qtbase
      qt5.qtserialport
      qt5.qtwebsockets
      sqlite
      hicolor_icon_theme
      libcap
      libpng
    ];
    runScript = "deCONZ";
  };
}
