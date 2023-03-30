{ stdenv, fetchFromGitHub, cmake, pkgconfig }:

stdenv.mkDerivation {
  name = "rockchip_mpp";
  version = "release_20170811";

  src = fetchFromGitHub {
    owner = "rockchip-linux";
    repo = "mpp";
    rev = "master";
    sha256 = "sha256-7VExpNdJI7FwtpLxWtb76cNwhzciWm9Pvoc05iND6FQ=";
  };

  postPatch = ''
    substituteInPlace pkgconfig/rockchip_mpp.pc.cmake \
      --replace 'libdir=''${prefix}/'     'libdir=' \
      --replace 'includedir=''${prefix}/' 'includedir='

    substituteInPlace pkgconfig/rockchip_vpu.pc.cmake \
      --replace 'libdir=''${prefix}/'     'libdir=' \
      --replace 'includedir=''${prefix}/' 'includedir='
  '';

  nativeBuildInputs = [ cmake pkgconfig ];

  cmakeFlags = [ "-DCMAKE_RKPLATFORM_ENABLE=ON" ];

  outputs = [ "lib" "dev" "out" ];
}
