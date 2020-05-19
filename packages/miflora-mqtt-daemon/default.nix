{ stdenv
, fetchFromGitHub
, python3
}:

stdenv.mkDerivation rec {
  pname = "miflora-mqtt-daemon";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "ThomDietrich";
    repo = pname;
    rev = "master";
    sha256 = "1494yl0kq0wgjg3fjqy21qr7dqhab0r6dm1xqiw1ad2vgj0b95fj";
  };


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
