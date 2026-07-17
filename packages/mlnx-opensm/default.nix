{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, dpkg
, rdma-core
}:

stdenv.mkDerivation {
  pname = "mlnx-opensm";
  version = "5.13.0.MLNX20221016.10d3954-0.1.58604";

  srcs = [
    (fetchurl {
      url = "https://linux.mellanox.com/public/repo/mlnx_ofed/latest-5.8/ubuntu20.04/amd64/opensm_5.13.0.MLNX20221016.10d3954-0.1.58604_amd64.deb";
      hash = "sha256-Vmab/h9yUTt0QFReacUadk9FfI5VY56ovSjbJb6Dzks=";
    })
    (fetchurl {
      url = "https://linux.mellanox.com/public/repo/mlnx_ofed/latest-5.8/ubuntu20.04/amd64/libopensm_5.13.0.MLNX20221016.10d3954-0.1.58604_amd64.deb";
      hash = "sha256-eumHO/R6BrAzi5KUqVudJxqTLzCwZ4Sc9V0/b7WXulo=";
    })
  ];

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
  ];
  buildInputs = [
    rdma-core
    stdenv.cc.cc.lib
  ];

  unpackPhase = ''
    runHook preUnpack
    for deb in $srcs; do
      dpkg-deb --extract "$deb" source
    done
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/lib" "$out/share"
    cp source/usr/sbin/opensm source/usr/sbin/osmtest "$out/bin/"
    cp -a source/usr/lib/libopen* source/usr/lib/libosm* "$out/lib/"
    cp -a source/usr/share/man source/usr/share/doc "$out/share/"
    runHook postInstall
  '';

  meta = {
    description = "NVIDIA MLNX_OFED OpenSM with virtualized InfiniBand vport support";
    homepage = "https://docs.nvidia.com/networking/display/mlnxofedv51258060/single+root+io+virtualization+(sr-iov)";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "opensm";
  };
}
