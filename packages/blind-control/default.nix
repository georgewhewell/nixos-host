{ stdenv
, python3
}:

let
  bluepy = python3.pkgs.callPackage ./bluepy.nix { };
in python3.pkgs.buildPythonApplication rec {
  pname = "blind_control";
  version = "1.3.0";

  src = ./blind_control;
  unpackPhase = null;

  propagatedBuildInputs = [ bluepy python3.pkgs.astral ];

  doCheck = false;

  meta = with stdenv.lib; {
    description = "let the light out";
    maintainers = with maintainers; [ georgewhewell ];
    license = licenses.gpl2;
  };

}
