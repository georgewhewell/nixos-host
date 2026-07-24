{
  stdenv,
  lib,
  kernel,
  kernelModuleMakeFlags,
  src,
}:

stdenv.mkDerivation {
  pname = "plx-sdk-svc";
  version = "8.23";

  inherit src;
  sourceRoot = "source";

  hardeningDisable = ["pic"];
  nativeBuildInputs = kernel.moduleBuildDependencies;
  patches = [./plx-svc-linux-7.2.patch];

  buildPhase = ''
    runHook preBuild
    export PLX_SDK_DIR="$PWD"
    make -C Driver \
      PLX_CHIP=Svc \
      PLX_NO_CLEAR_SCREEN=1 \
      KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      ${lib.escapeShellArgs kernelModuleMakeFlags} \
      V=1
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -D Driver/Source.PlxSvc/Output/PlxSvc.ko \
      "$out/lib/modules/${kernel.modDirVersion}/kernel/drivers/misc/PlxSvc.ko"
    runHook postInstall
  '';

  meta = {
    description = "Broadcom PLX SDK PCI/PCIe service driver";
    homepage = "https://www.broadcom.com/products/pcie-switches-retimers";
    license = with lib.licenses; [gpl2Only bsd2];
    platforms = lib.platforms.linux;
  };
}
