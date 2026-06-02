self: super: {
  # U-Boot for NanoPi NEO2 (Allwinner H5)
  ubootNanoPiNeo2 = super.ubootPine64.override {
    defconfig = "nanopi_neo2_defconfig";
  };

  # Minimal vim without GUI/scripting for headless servers
  # Reduces closure from 483MB to ~30MB
  vim-minimal = super.vim-full.override {
    guiSupport = false;
    pythonSupport = false;
    luaSupport = false;
    rubySupport = false;
    perlSupport = false;
    tclSupport = false;
  };

  # Fix mtail cross-compilation - upstream vendor directory is out of sync
  mtail = super.mtail.overrideAttrs (old: {
    proxyVendor = true;
    vendorHash = "sha256-QWIVIEhnDoU8omWEL2GJLUCr3U7fqJ5znTt7yehtq8g=";
  });

  apple-health-ingester = super.callPackage ../packages/apple-health-ingester {};

  home-assistant-cli-go = super.buildGoModule rec {
    pname = "home-assistant-cli-go";
    version = "4.39.0";

    src = super.fetchFromGitHub {
      owner = "home-assistant";
      repo = "cli";
      rev = version;
      hash = "sha256-iBLDa1gEm6a8DndxI9ne8WSzzo12wNhXMfVpri3UkW8=";
    };

    vendorHash = "sha256-33ghWEgTuTyqFq9YxiSCFnZPry+21ap0jCn8EDa+cGE=";

    postInstall = ''
      mv $out/bin/cli $out/bin/ha
    '';

    meta = with super.lib; {
      description = "Command line interface to facilitate interaction with the Home Assistant Supervisor";
      homepage = "https://github.com/home-assistant/cli";
      license = licenses.asl20;
      maintainers = with maintainers; [];
      mainProgram = "ha";
    };
  };

  rockchip-mpp = super.callPackage ../packages/rockchip-mpp {};

  # ffmpeg with Rockchip MPP hardware encoding support (nyanmisaka fork)
  ffmpeg-rockchip = super.ffmpeg-headless.overrideAttrs (old: {
    src = super.fetchFromGitHub {
      owner = "nyanmisaka";
      repo = "ffmpeg-rockchip";
      rev = "8.0";
      hash = "sha256-mds5Djgc7IFmDhXmDkdW3vwONj5HYQXXCZTBxv6zhIU=";
    };
    patches = builtins.filter (p:
      !(builtins.isPath p && builtins.match ".*hardcoded-tables.*" (toString p) != null)
      && !(builtins.isAttrs p && builtins.match ".*hardcoded-tables.*" (p.name or "") != null)
    ) (old.patches or []);
    buildInputs = (old.buildInputs or []) ++ [self.rockchip-mpp super.libdrm];
    configureFlags = (old.configureFlags or []) ++ ["--enable-rkmpp"];
  });

  hostapd-exporter = super.callPackage ../packages/hostapd-exporter {};
  nvidia_oc = super.callPackage ../packages/nvidia-oc {};

  # llama-cpp = super.llama-cpp.overrideAttrs (oldAttrs: rec {
  #   version = "HEAD";
  #   src = super.fetchFromGitHub {
  #     owner = "ggerganov";
  #     repo = "llama.cpp";
  #     rev = "HEAD";
  #     hash = "sha256-I1X+xRk4qVnGZWavS8XY5IcQBZXdMoKLa/G/2Tmefbc=";
  #   };
  # });

  xmrig-cuda-plugin = let
    version = "6.22.1";
    _cudaPackages = super.cudaPackages_13;
  in
    super.stdenv.mkDerivation {
      name = "xmrig-cuda";
      version = version;
      hardeningDisable = ["all"];
      src = super.fetchFromGitHub {
        owner = "xmrig";
        repo = "xmrig-cuda";
        rev = "v${version}";
        sha256 = "sha256-krS0ygKclXDLti24PDnBFUetOAYkYM8jty4C3PSOEWY=";
      };

      buildInputs = with _cudaPackages; [
        cuda_cudart
        cuda_nvrtc
        cuda_nvml_dev
        cuda_nvcc
      ];

      nativeBuildInputs = with super; [
        cmake
        # autoPatchelfHook
        autoAddDriverRunpath
        _cudaPackages.cuda_nvcc
      ];

      propagatedBuildInputs = [_cudaPackages.cuda_nvml_dev];

      postPatch = ''
        # CUDA 13 removed deprecated clockRate/memoryClockRate from cudaDeviceProp
        sed -i '/props\.clockRate/d; /props\.memoryClockRate/d' src/cuda_extra.cu
      '';

      configurePhase = ''
        mkdir -p build
      '';

      buildPhase = ''
        cd build
        cmake .. -DCMAKE_CUDA_ARCHITECTURES=89 -DCUDA_ARCH="89" -DCUDA_LIB=${super.lib.getDev _cudaPackages.cuda_cudart}/lib/stubs/libcuda.so -DCUDA_TOOLKIT_ROOT_DIR=${super.lib.getDev _cudaPackages.cuda_cudart} -DCMAKE_C_COMPILER=${super.gcc13}/bin/gcc
        make -j$(nproc)
      '';

      installPhase = ''
        cp -r /build/source/build $out
      '';

      meta = with super.lib; {
        description = "NVIDIA CUDA plugin for XMRig miner";
        homepage = "https://github.com/xmrig/xmrig-cuda";
        license = licenses.mit;
        platforms = platforms.linux;
      };
    };

  xmrig-rock5b = super.xmrig.overrideAttrs (oldAttrs: {
    NIX_CFLAGS_COMPILE = toString [
      "-O3"
      "-march=armv8.2-a+crypto+dotprod"
      "-mtune=cortex-a76.cortex-a55"
      "-fomit-frame-pointer"
      "-pipe"
      "-fno-stack-protector"
    ];
    NIX_CFLAGS_LINK = "-Wl,-z,norelro";
    hardeningDisable = ["all"];
  });

  xmrig-alderlake = super.xmrig.overrideAttrs (oldAttrs: {
    NIX_CFLAGS_COMPILE = toString [
      "-O3"
      "-march=alderlake"
      "-mtune=alderlake"
      "-fomit-frame-pointer"
      "-pipe"
      "-fno-stack-protector"
    ];
    NIX_CFLAGS_LINK = "-Wl,-z,norelro";
    hardeningDisable = ["all"];
  });

  xmrig-zen4 = super.xmrig.overrideAttrs (oldAttrs: {
    cmakeFlags = [
      "-DWITH_SSE4_1=ON"
    ];
    NIX_CFLAGS_COMPILE = toString [
      "-O3"
      "-march=znver4"
      "-mtune=znver4"
      "-fomit-frame-pointer"
      "-pipe"
      "-fno-stack-protector"
    ];
    NIX_CFLAGS_LINK = "-Wl,-z,norelro";
    hardeningDisable = ["all"];
  });

  xmrig-zen5 = super.xmrig.overrideAttrs (oldAttrs: {
    cmakeFlags = [
      "-DWITH_SSE4_1=ON"
    ];
    NIX_CFLAGS_COMPILE = toString [
      "-O3"
      "-march=znver5"
      "-mtune=znver5"
      "-fomit-frame-pointer"
      "-pipe"
      "-fno-stack-protector"
    ];
    NIX_CFLAGS_LINK = "-Wl,-z,norelro";
    hardeningDisable = ["all"];
  });

  wakiki-fw = super.stdenvNoCC.mkDerivation {
    name = "wakiki-firmware";
    src = ../packages/wakiki-fw;

    installPhase = ''
      echo $(ls -la)
      mkdir -p $out/lib/firmware/ath12k/QCN9274/hw2.0
      # Copy firmware files but skip regdb.bin to use global regulatory
      cp board.bin $out/lib/firmware/ath12k/QCN9274/hw2.0/
      cp firmware-2.bin $out/lib/firmware/ath12k/QCN9274/hw2.0/
      # cp regdb.bin $out/lib/firmware/regdb.bin
    '';
  };

  ath12k-fw = super.stdenvNoCC.mkDerivation {
    name = "ath12k-firmware";
    src = super.fetchFromGitLab {
      domain = "git.codelinaro.org";
      owner = "clo";
      repo = "ath-firmware/ath12k-firmware";
      rev = "bbf6fa9186cc475e17293b365624d1c19f43884f";
      hash = "sha256-u1kUgdH9bliWS+EHcrfgHIY8ssrs9GL0eZYvkcmm7Og=";
    };

    dontBuild = true;

    installPhase = ''
      mkdir -p $out/lib/firmware/ath12k/QCN9274/hw2.0
      # Copy board configuration and firmware files
      cp QCN9274/hw2.0/board-2.bin $out/lib/firmware/ath12k/QCN9274/hw2.0/
      # Copy latest firmware-2.bin from version 1.5
      cp QCN9274/hw2.0/1.5/WLAN.WBE.1.5-01651-QCAHKSWPL_SILICONZ-1/firmware-2.bin $out/lib/firmware/ath12k/QCN9274/hw2.0/
      # Skip regdb.bin to use global regulatory database
      # cp QCN9274/hw2.0/regdb.bin $out/lib/firmware/ath12k/QCN9274/hw2.0/
    '';
  };

  tari = super.callPackage ../packages/tari {};

  scion = super.callPackage ../packages/scion {};
  scion-claude-image = super.callPackage ../packages/scion/image.nix {
    scion = self.scion;
    # antigravity isn't in nixpkgs yet; it ships in the nix-ai-tools flake.
    # Threaded in via specialArgs from flake.nix where the input is in scope.
    inherit (self) antigravity;
  };

  p2pool = super.p2pool.overrideAttrs (oldAttrs: rec {
    pname = "p2pool";
    version = "4.14";
    src = super.fetchFromGitHub {
      owner = "SChernykh";
      repo = "p2pool";
      rev = "v${version}";
      hash = "sha256-osVzCx5h52qbSG4iwd3r7lsxtkqakGDJp6W3Xfs0t4E=";
      fetchSubmodules = true;
    };
  });

  # LTX-2 video generation model - extend python package sets
  pythonPackagesExtensions =
    super.pythonPackagesExtensions
    ++ [
      (python-final: python-prev: {
        # accelerate tests fail on builders without GPU (rocm) or missing nvidia-ml-py (cuda)
        accelerate = python-prev.accelerate.overridePythonAttrs (old:
          super.lib.optionalAttrs ((super.config.rocmSupport or false) || (super.config.cudaSupport or false)) {
            doCheck = false;
          });
        # Torchaudio's GPU test suite is not stable under the ROCm/CUDA
        # package sets used by the builders; keep the package buildable.
        torchaudio = python-prev.torchaudio.overridePythonAttrs (old:
          super.lib.optionalAttrs ((super.config.rocmSupport or false) || (super.config.cudaSupport or false)) {
            doCheck = false;
          });
        ltx-core = python-final.callPackage ../packages/python-libraries/ltx-core {
          cudaSupport = super.config.cudaSupport or false;
        };
        ltx-pipelines = python-final.callPackage ../packages/python-libraries/ltx-pipelines {
          inherit (python-final) ltx-core;
        };
      })
    ];

  # Also expose as top-level for convenience
  ltx-2 = super.python3Packages.ltx-pipelines;

  easyeda2kicad = super.callPackage ../packages/easyeda2kicad {};

}
