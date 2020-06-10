{ stdenv
, fswebcam
, ffmpeg
, python3
}:

python3.pkgs.buildPythonApplication rec {
  pname = "entking";
  version = "0.1.0";

  src = ./src;
  unpackPhase = null;

  propagatedBuildInputs = with python3.pkgs; [
    flask
    smbus2
    miflora
#    fswebcam
#    ffmpeg
  ];

  doCheck = false;

  meta = with stdenv.lib; {
    description = "water the plant";
    maintainers = with maintainers; [ georgewhewell ];
    license = licenses.gpl2;
  };

}
