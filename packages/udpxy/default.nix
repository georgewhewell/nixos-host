{ openssl
, pkg-config
, gcc6Stdenv
, gzip
, fetchFromGitHub
}:

gcc6Stdenv.mkDerivation rec {
  pname = "udpxy";
  version = "udpxy";

  src = fetchFromGitHub {
    owner = "pcherenkov";
    repo = "udpxy";
    rev = "master";
    sha256 = "sha256-J7NuVD+4GfPGi984WXCXG6MBAFeTM2KMzW2PzlbS0NI=";
  };

  patches = [ ./fix-size-0.patch ];
  postPatch = ''
    substituteInPlace Makefile --replace "/bin/gzip" "${gzip}/bin/gzip"
  '';

  postInstall = ''
    mkdir $out/bin
    cp ./udpxy $out/bin/udpxy
  '';

  sourceRoot = "source/chipmunk";
  nativeBuildInputs = [ pkg-config ];
  makeFlags = [ "DESTDIR=$out" "PREFIX=" ];
  buildInputs = [ openssl ];

}
