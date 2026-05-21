{
  stdenv,
  fetchFromGitHub,
  cmake,
}:

stdenv.mkDerivation rec {
  pname = "rockchip-mpp";
  version = "unstable-2026-04-19";

  src = fetchFromGitHub {
    owner = "rockchip-linux";
    repo = "mpp";
    rev = "develop";
    hash = "sha256-eZ3XOSWh2Bvib+OHGtrXw41BK6yh5pMJnSrA7tRR0YI=";
  };

  nativeBuildInputs = [cmake];

  cmakeFlags = [
    "-DRKPLATFORM=ON"
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    "-DBUILD_TEST=OFF"
  ];

  postPatch = ''
    substituteInPlace pkgconfig/rockchip_mpp.pc.cmake \
      --replace-fail 'libdir=''${prefix}/'     'libdir=' \
      --replace-fail 'includedir=''${prefix}/' 'includedir='
    substituteInPlace pkgconfig/rockchip_vpu.pc.cmake \
      --replace-fail 'libdir=''${prefix}/'     'libdir=' \
      --replace-fail 'includedir=''${prefix}/' 'includedir='
    # Stub out the POST_BUILD merge_static_lib script that doesn't exist outside BSP
    echo '#!/bin/sh' > merge_static_lib.sh
    chmod +x merge_static_lib.sh
  '';
}
