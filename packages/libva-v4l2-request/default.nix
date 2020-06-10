{ stdenv
, sources
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
  version = sources.libva-v4l2-request.rev;

  src = sources.libva-v4l2-request;

  buildInputs = [ libva libdrm ];
  nativeBuildInputs = [ meson ninja pkg-config cmake ];

  patches = [ ./remove_tiled_to_planar.patch ];

}
