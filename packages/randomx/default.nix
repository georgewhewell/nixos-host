{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
}:

stdenv.mkDerivation rec {
  pname = "randomx";
  version = "1.2.1";

  src = fetchFromGitHub {
    owner = "tevador";
    repo = "RandomX";
    rev = "v${version}";
    hash = "sha256-1wwfbxxrzzps9dm1fm915dv3l8hym5na2hpnd0f98z640v7jdwkm";
  };

  nativeBuildInputs = [cmake];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
  ];

  meta = with lib; {
    description = "Proof of work algorithm based on random code execution";
    homepage = "https://github.com/tevador/RandomX";
    license = licenses.bsd3;
    maintainers = [];
  };
}
