final:
let
  inherit (final) lib linuxKernel;
  inherit (lib.kernel) yes no;

  cfg = config: kernel: kernel.override {
    kernelPatches = kernel.kernelPatches;
    structuredExtraConfig = kernel.structuredExtraConfig // config;
  };

  llvm = kernel:
    let
      llvmPackages = "llvmPackages_17";
      noBintools = { bootBintools = null; bootBintoolsNoLibc = null; };
      hostLLVM = final.pkgsBuildHost.${llvmPackages}.override noBintools;
      buildLLVM = final.pkgsBuildBuild.${llvmPackages}.override noBintools;

      mkLLVMPlatform = platform: platform // {
        useLLVM = true;
        linux-kernel = platform.linux-kernel // {
          makeFlags = (platform.linux-kernel.makeFlags or [ ]) ++ [
            "LLVM=1"
            "LLVM_IAS=1"
            "CC=${buildLLVM.clangUseLLVM}/bin/clang"
            "LD=${buildLLVM.lld}/bin/ld.lld"
            "HOSTLD=${hostLLVM.lld}/bin/ld.lld"
            "AR=${buildLLVM.llvm}/bin/llvm-ar"
            "HOSTAR=${hostLLVM.llvm}/bin/llvm-ar"
            "NM=${buildLLVM.llvm}/bin/llvm-nm"
            "STRIP=${buildLLVM.llvm}/bin/llvm-strip"
            "OBJCOPY=${buildLLVM.llvm}/bin/llvm-objcopy"
            "OBJDUMP=${buildLLVM.llvm}/bin/llvm-objdump"
            "READELF=${buildLLVM.llvm}/bin/llvm-readelf"
            "HOSTCC=${hostLLVM.clangUseLLVM}/bin/clang"
            "HOSTCXX=${hostLLVM.clangUseLLVM}/bin/clang++"
          ];
        };
      };
      stdenvClangUseLLVM = final.overrideCC hostLLVM.stdenv hostLLVM.clangUseLLVM;
      stdenvPlatformLLVM = stdenvClangUseLLVM.override (old: {
        hostPlatform = mkLLVMPlatform old.hostPlatform;
        buildPlatform = mkLLVMPlatform old.buildPlatform;
      });
      stdenv = stdenvPlatformLLVM;
    in
    kernel.override {
      inherit stdenv;
      buildPackages = final.buildPackages // { inherit stdenv; };
      argsOverride.kernelPatches = kernel.kernelPatches;
      argsOverride.structuredExtraConfig = kernel.structuredExtraConfig;
    };

  fullLTO = kernel:
    cfg
      { LTO_NONE = no; LTO_CLANG_FULL = yes; LRU_GEN = yes; LRU_GEN_ENABLED = yes; }
      (llvm kernel);

  patch = patches: kernel: kernel.override {
    argsOverride.kernelPatches = kernel.kernelPatches ++ patches;
    argsOverride.structuredExtraConfig = kernel.structuredExtraConfig;
  };

  patches = {
    graysky_lt_6_8 = {
      name = "more-uarches-for-kernel-6.1.79-6.8-rc3";
      patch = final.fetchpatch {
        name = "more-uarches-for-kernel-6.1.79-6.8-rc3";
        url = "https://raw.githubusercontent.com/graysky2/kernel_compiler_patch/master/more-uarches-for-kernel-6.1.79-6.8-rc3.patch";
        hash = "sha256-ZEeeQViUZWunzZzeJ6z9/RwoNaQzzJK7q1yBUh4weXE=";
      };
    };
    graysky = {
      name = "more-uarches-for-kernel-6.8-rc4+.patch";
      patch = final.fetchpatch {
        name = "more-uarches-for-kernel-6.8-rc4+.patch";
        url = "https://raw.githubusercontent.com/graysky2/kernel_compiler_patch/master/more-uarches-for-kernel-6.8-rc4%2B.patch";
        hash = "sha256-VjdF4DC/midcNGcYGrquLwCpkZKeghVbWI3S9++RTV8=";
      };
    };
  };

  inherit (linuxKernel) kernels packagesFor;

  latest = kernels.linux_6_8;
  latest_zfs = kernels.linux_6_7;

in
_: {
  linuxPackages_latest_lto = packagesFor (fullLTO latest);
  linuxPackages_latest_lto_skylake = packagesFor
    (cfg
      { MSKYLAKE = yes; }
      (patch
        [ patches.graysky ]
        (fullLTO latest)));

  linuxPackages_lto_broadwell = packagesFor
    (cfg
      { MBROADWELL = yes; }
      (patch
        [ patches.graysky ]
        (fullLTO latest)));

  linuxPackages_latest_lto_silvermont = packagesFor
    (cfg
      { MSILVERMONT = yes; }
      (patch
        [ patches.graysky ]
        (fullLTO latest)));

  linuxPackages_latest_lto_zen4 = packagesFor
    (cfg
      { MZEN4 = yes; }
      (patch
        [ patches.graysky ]
        (fullLTO latest)));

  linuxPackages_latest_lto_icelake = packagesFor
    (cfg
      { MICELAKE = yes; NR_CPUS = 4; }
      (patch
        [ patches.graysky ]
        (fullLTO latest)));
}
