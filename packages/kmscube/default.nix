{ pkgs ? import <nixpkgs> { } }:

with pkgs;
with stdenv.lib;

stdenv.mkDerivation rec {
  name = "veriumd-${version}";
  version = "unstable";

  src = fetchFromGitHub {
    owner = "robclark";
    repo = "kmscube";
    rev = "56c3917ffd1f05942246e2532ca4a5707554a2fc";
    sha256 = "0gw45fj816vw12f1yjgxi96hf90qj8mjwy748b9nq5fdwx8qm59l";
  };

  enableParallelBuilding = true;
  installPhase = ''
    mkdir -p $out/bin
    cp kmscube $out/bin
  '';
  nativeBuildInputs = [ autoreconfHook pkgconfig libdrm ];
  /* buildInputs = []; */


  meta = {
    description = "Peer-to-peer electronic cash system";
    maintainers = with maintainers; [ georgewhewell ];
    platforms = platforms.unix;
  };
}
