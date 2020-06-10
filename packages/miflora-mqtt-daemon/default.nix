{ stdenv
, sources
, fetchFromGitHub
, python3
}:

stdenv.mkDerivation rec {
  pname = "miflora-mqtt-daemon";
  version = "master";

  src = sources.miflora-mqtt-daemon;

  buildInputs = [
    (python3.withPackages (ps: with ps; [
      miflora
      btlewrap
      paho-mqtt
      colorama
      unidecode
      sdnotify
    ]))
  ];

  installPhase = "install -m755 -D miflora-mqtt-daemon.py $out/bin/miflora-mqtt-daemon";

  doCheck = false;

  meta = with stdenv.lib; {
    description = "water the plant";
    maintainers = with maintainers; [ georgewhewell ];
    license = licenses.gpl2;
  };

}
