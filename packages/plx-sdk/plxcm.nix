{
  stdenv,
  lib,
  gnumake,
  src,
}:

stdenv.mkDerivation {
  pname = "plxcm";
  version = "8.23";

  inherit src;
  sourceRoot = "source";

  nativeBuildInputs = [gnumake];

  buildPhase = ''
    runHook preBuild
    export PLX_SDK_DIR="$PWD"
    make -C PlxApi \
      PLX_NO_CLEAR_SCREEN=1 \
      ARCH=${stdenv.hostPlatform.linuxArch} \
      CROSS_COMPILE=${stdenv.cc.targetPrefix}
    make -C Samples/PlxCm \
      PLX_NO_CLEAR_SCREEN=1 \
      ARCH=${stdenv.hostPlatform.linuxArch} \
      CROSS_COMPILE=${stdenv.cc.targetPrefix}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -D Samples/PlxCm/App/PlxCm "$out/bin/PlxCm"
    install -D Samples/PlxCm/PlxCm_README.txt \
      "$out/share/doc/plxcm/PlxCm_README.txt"
    runHook postInstall
  '';

  meta = {
    description = "Broadcom PLX command-line console monitor";
    homepage = "https://www.broadcom.com/products/pcie-switches-retimers";
    license = with lib.licenses; [gpl2Only bsd2];
    mainProgram = "PlxCm";
    platforms = lib.platforms.linux;
  };
}
