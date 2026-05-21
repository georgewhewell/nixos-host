{
  stdenv,
  lib,
  fetchFromGitHub,
  kernel,
  kernelModuleMakeFlags,
}:

stdenv.mkDerivation {
  pname = "r8127";
  version = "11.015.00-unstable-2025-10-27";

  src = fetchFromGitHub {
    owner = "openwrt";
    repo = "rtl8127";
    rev = "f80bc64922ac76f90618f61245fb29743c018d0a";
    hash = "sha256-EBCEhtRqqZDjGrkQdjF5GozfreELX8wr9UseMucMOB4=";
  };

  hardeningDisable = ["pic"];

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = kernelModuleMakeFlags ++ [
    "KERNELDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "ENABLE_RSS_SUPPORT=y"
    "ENABLE_MULTIPLE_TX_QUEUE=y"
  ];

  buildFlags = ["modules"];

  installPhase = ''
    runHook preInstall
    install -D r8127.ko $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/net/ethernet/realtek/r8127.ko
    runHook postInstall
  '';

  meta = {
    homepage = "https://github.com/openwrt/rtl8127";
    description = "Realtek r8127 10GbE Ethernet driver";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
