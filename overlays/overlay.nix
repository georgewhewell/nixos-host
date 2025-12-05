self: super: {
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

  hostapd-exporter = super.callPackage ../packages/hostapd-exporter {};

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
    _cudaPackages = super.cudaPackages;
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

      configurePhase = ''
        mkdir -p build
      '';

      buildPhase = ''
        cd build
        cmake .. -DCMAKE_CUDA_ARCHITECTURES=89 -DCUDA_LIB=${super.lib.getDev _cudaPackages.cuda_cudart}/lib/stubs/libcuda.so -DCUDA_TOOLKIT_ROOT_DIR=${super.lib.getDev _cudaPackages.cuda_cudart} -DCMAKE_C_COMPILER=${super.gcc13}/bin/gcc
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

  xmrig = super.xmrig.override {
    stdenv = super.gcc15Stdenv;
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

  # librespot = super.librespot.overrideAttrs (oldAttrs: rec {
  #   pname = "librespot";
  #   version = "0.7.0";

  #   src = super.fetchFromGitHub {
  #     owner = "librespot-org";
  #     repo = "librespot";
  #     rev = "v${version}";
  #     sha256 = "sha256-dGQDRb5fgIkXelZKa+PdodIs9DxbgEMlVGJjK/hU3Mo=";
  #   };
  # });

  # spotifyd = super.spotifyd.overrideAttrs (oldAttrs: rec {
  #   pname = "spotifyd";
  #   version = "0.3.4";

  #   src = super.fetchFromGitHub {
  #     owner = "fabienjuif";
  #     repo = "spotifyd";
  #     rev = "hotfix_librespot_0.7";
  #     sha256 = "sha256-OvywtwFg5dGHPSgtMGIrA8NxkaEAdXtlFPXQZo6xR1o=";
  #   };
  #   cargoHash = "";
  # });
  tari = super.callPackage ../packages/tari {};

  p2pool = super.p2pool.overrideAttrs (oldAttrs: rec {
    pname = "p2pool";
    version = "4.12";
    src = super.fetchFromGitHub {
      owner = "SChernykh";
      repo = "p2pool";
      rev = "v${version}";
      hash = "sha256-Yrc36tibHanXZcE3I+xcmkCzBALE09zi1Zg0Lz3qS2g=";
      fetchSubmodules = true;
    };
  });
}
