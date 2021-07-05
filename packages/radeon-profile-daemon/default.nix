{ lib, stdenv, fetchFromGitHub
, sources
, qtbase, qtcharts, qmake, libXrandr, libdrm, wrapQtAppsHook
}:

stdenv.mkDerivation rec {

  pname = "radeon-profile-daemon";
  version = "20190903";

  nativeBuildInputs = [ qmake ];
  buildInputs = [ qtbase qtcharts libXrandr libdrm wrapQtAppsHook ];

  src = (sources.radeon-profile-daemon) + "/radeon-profile-daemon";

  preConfigure = ''
    substituteInPlace radeon-profile-daemon.pro \
      --replace "/usr/" "$out/"
  '';

  meta = with lib; {
    description = "Application to read current clocks of AMD Radeon cards";
    homepage    = "https://github.com/marazmista/radeon-profile";
    license     = licenses.gpl2Plus;
    platforms   = platforms.linux;
  };

}
