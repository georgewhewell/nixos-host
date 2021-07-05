{
  stdenv,
  lib,
  fetchFromGitHub,
  opencl-headers,
  cmake,
  jsoncpp,
  boost,
  makeWrapper,
  mesa,
  ethash,
  opencl-info,
  ocl-icd,
  openssl,
  pkg-config,
  cli11
}:

stdenv.mkDerivation rec {
  pname = "ethminer";
  version = "0.19.0";

  src =
    fetchFromGitHub {
      owner = "ethereum-mining";
      repo = "ethminer";
      rev = "ce52c74021b6fbaaddea3c3c52f64f24e39ea3e9";
      sha256 = "03ba55spbi42p5djqaqb41ywgw2g1smky3qmc9s3309p8cvnqcf9";
      fetchSubmodules = true;
    };

  # NOTE: dbus is broken
  cmakeFlags = [
    "-DHUNTER_ENABLED=OFF"
    "-DETHASHCUDA=OFF"
    "-DAPICORE=ON"
    "-DETHDBUS=OFF"
    "-DCMAKE_BUILD_TYPE=Release"
  ];

  nativeBuildInputs = [
    cmake
    pkg-config
    makeWrapper
  ];

  buildInputs = [
    cli11
    boost
    opencl-headers
    mesa
    ethash
    opencl-info
    ocl-icd
    openssl
    jsoncpp
  ];

  dontStrip = true;
  hardeningDisable = [ "all" ];

  preConfigure = ''
    sed -i 's/_lib_static//' libpoolprotocols/CMakeLists.txt
  '';

  postInstall = ''
    wrapProgram $out/bin/ethminer --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib
  '';

  meta = with lib; {
    description = "Ethereum miner with OpenCL, CUDA and stratum support";
    homepage = "https://github.com/ethereum-mining/ethminer";
    platforms = [ "x86_64-linux" ];
    maintainers = with maintainers; [ nand0p ];
    license = licenses.gpl2;
  };

}
