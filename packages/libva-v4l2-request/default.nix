{ stdenv
, fetchFromGitHub
, meson
, ninja
, cmake
, pkg-config
, libva
, libdrm
, autoreconfHook
}:

stdenv.mkDerivation rec {
  pname = "libva-v4l2-request";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "bootlin";
    repo = "libva-v4l2-request";
    rev = "a3c2476de19e6635458273ceeaeceff124fabd63";
    sha256 = "1sbfg5qybahmchwjbm81rmxxxqvbp0dzi4zzqmwb1mzs3asqc3m3";
  };

  buildInputs = [ libva libdrm ];
  nativeBuildInputs = [ meson ninja pkg-config cmake ];

  patches = [ ./remove_tiled_to_planar.patch ];

}
