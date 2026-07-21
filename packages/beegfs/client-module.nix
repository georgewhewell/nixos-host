{ stdenv
, lib
, fetchFromGitHub
, kernel
, bash
, gawk
, which
}:

# BeeGFS client kernel module. Build with:
#   config.boot.kernelPackages.callPackage ../../../packages/beegfs/client-module.nix { }
# Kernel compatibility is handled by upstream's compile-time feature probes
# (client_module/build/feature-detect.sh), not version ifdefs — new kernels
# usually need probe/API fixes rather than wholesale porting.
stdenv.mkDerivation rec {
  pname = "beegfs-client-module";
  # Keep in lockstep with ../beegfs/default.nix (same rev).
  version = "8.4.0-unstable-2026-07-15";

  src = fetchFromGitHub {
    owner = "ThinkParQ";
    repo = "beegfs";
    rev = "775cf9291b0b690a729221d67eb01bc3579023c0";
    hash = "sha256-2ihlQ6dCfbivP+MnaIhBkfQHeNgvRJhkX4M8hvZdvuQ=";
  };

  hardeningDisable = [ "pic" ];

  # Kernel >= 7.x compat: linux/pagevec.h removed (include was vestigial),
  # strncpy removed from kernel string.h (strscpy is the sanctioned
  # replacement; upstream already uses it for the strlcpy removal).
  patches = [ ./client-kernel7-compat.patch ];

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [ gawk which ];

  # feature-detect.sh is a bash script invoked from Kbuild.
  postPatch = ''
    patchShebangs client_module/build
    # Hardcoded /bin/true doesn't exist in the sandbox.
    sed -i 's,/bin/true,true,g' client_module/build/Makefile
  '';

  makeFlags = [
    "-C" "client_module/build"
    "ARCH=${stdenv.hostPlatform.linuxArch}"
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "KRELEASE=${kernel.modDirVersion}"
    "BEEGFS_VERSION=${version}"
  ] ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
    "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
  ];

  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall
    install -D client_module/build/beegfs.ko \
      $out/lib/modules/${kernel.modDirVersion}/kernel/fs/beegfs/beegfs.ko
    runHook postInstall
  '';

  meta = {
    description = "BeeGFS parallel filesystem client kernel module";
    homepage = "https://www.beegfs.io";
    license = lib.licenses.gpl2Only; # client module is GPLv2
    platforms = lib.platforms.linux;
  };
}
