{
  lib,
  python3Packages,
  fetchFromGitHub,
}:
python3Packages.buildPythonApplication rec {
  pname = "easyeda2kicad";
  version = "0.8.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "uPesy";
    repo = "easyeda2kicad.py";
    rev = "b477d9d4dfdb9a030a284a0644cd594b9a02cef0";
    hash = "sha256-3Nray+gN4yahMddzsk3Hn0yTc/wDcGAGzsUOhvi2TwU=";
  };

  build-system = with python3Packages; [
    setuptools
  ];

  dependencies = with python3Packages; [
    pydantic
    requests
  ];

  meta = with lib; {
    description = "Convert EasyEDA/LCSC components to KiCad library files";
    homepage = "https://github.com/uPesy/easyeda2kicad.py";
    license = licenses.agpl3Only;
    maintainers = [];
    mainProgram = "easyeda2kicad";
  };
}
