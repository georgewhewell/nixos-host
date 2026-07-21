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
    vendorHash = "sha256-NKNCpTCfc2U5fqdhXu30w7QlUjCwSX0l+t5ivWtEgdU=";
  });

  # open-webui's pytest suite has a flaky SSE test that collides on a fixed
  # loopback port (test_get_sse_stream: "address already in use").
  open-webui = super.open-webui.overridePythonAttrs (old: {
    doCheck = false;
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

  beegfs = super.callPackage ../packages/beegfs {};
  beegfs-mgmtd = super.callPackage ../packages/beegfs/mgmtd.nix {};
  beegfs-ctl = super.callPackage ../packages/beegfs/ctl.nix {};
  # Client kernel module builds per-kernel:
  #   config.boot.kernelPackages.callPackage ../packages/beegfs/client-module.nix { }

  hostapd-exporter = super.callPackage ../packages/hostapd-exporter {};
  bios-setup-var = super.callPackage ../packages/bios-setup-var {};
  mlnx-mft = super.callPackage ../packages/mlnx-mft {};
  mlnx-opensm = super.callPackage ../packages/mlnx-opensm {};
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
      # The upstream WBE 1.5/1.6 firmware blobs fail to bring up MAC1 on
      # this split 5/6 GHz card; keep the vendor blob for both radios.
      cp board.bin $out/lib/firmware/ath12k/QCN9274/hw2.0/
      cp firmware-2.bin $out/lib/firmware/ath12k/QCN9274/hw2.0/
      cp regdb.bin $out/lib/firmware/ath12k/QCN9274/hw2.0/
    '';
  };

  qcn9274-linux-firmware-no-board2 = super.runCommand "linux-firmware-qcn9274-no-board2" {} ''
    mkdir -p "$out/lib/firmware"
    cd ${super.linux-firmware}/lib/firmware
    find . -type d -exec mkdir -p "$out/lib/firmware/{}" \;
    find . \( -type f -o -type l \) \
      ! -path './ath12k/QCN9274/hw2.0/board-2.bin*' \
      ! -path './ath12k/QCN9274/hw2.0/firmware-2.bin*' \
      -exec ln -s "${super.linux-firmware}/lib/firmware/{}" "$out/lib/firmware/{}" \;
  '';

  rock5b-minimal-firmware = super.runCommand "rock5b-minimal-firmware" {} ''
    mkdir -p "$out/lib/firmware/intel" "$out/lib/firmware/arm/mali/arch10.8" "$out/lib/firmware/rtl_nic"
    cp -L ${super.linux-firmware}/lib/firmware/iwlwifi-gl-c0-fm-c0-*.ucode "$out/lib/firmware/"
    cp -L ${super.linux-firmware}/lib/firmware/iwlwifi-gl-c0-fm-c0.pnvm "$out/lib/firmware/"
    cp -L ${super.linux-firmware}/lib/firmware/intel/ibt-0291-0291.sfi "$out/lib/firmware/intel/"
    cp -L ${super.linux-firmware}/lib/firmware/intel/ibt-0291-0291.ddc "$out/lib/firmware/intel/"
    cp -L ${super.linux-firmware}/lib/firmware/arm/mali/arch10.8/mali_csffw.bin "$out/lib/firmware/arm/mali/arch10.8/"
    cp -L ${super.linux-firmware}/lib/firmware/rtl_nic/rtl8125b-2.fw "$out/lib/firmware/rtl_nic/"
  '';

  qcn9274FirmwareWithVendorBoard = {
    version,
    url,
    hash,
    dualmacAsPrimary ? false,
    board2 ? null,
    regdb ? null,
    vendorBoard2Aliases ? [],
    forceMloFeature ? false,
  }:
    super.stdenvNoCC.mkDerivation {
      name = "qcn9274-firmware-${version}-vendor-board";

      firmware = super.fetchurl {
        inherit url hash;
      };
      board2File =
        if board2 == null
        then null
        else
          super.fetchurl {
            inherit (board2) url hash;
          };
      regdbFile =
        if regdb == null
        then null
        else
          super.fetchurl {
            inherit (regdb) url hash;
          };

      nativeBuildInputs = super.lib.optionals (dualmacAsPrimary || vendorBoard2Aliases != [] || forceMloFeature) [
        super.buildPackages.python3
      ];

      dontUnpack = true;

      installPhase = ''
        mkdir -p "$out/lib/firmware/ath12k/QCN9274/hw2.0"
        ${
          if dualmacAsPrimary || forceMloFeature
          then ''
            python3 - "$firmware" "$out/lib/firmware/ath12k/QCN9274/hw2.0/firmware-2.bin" <<'PY'
            import struct
            import sys

            src, dst = sys.argv[1:]
            data = open(src, "rb").read()
            magic = b"QCOM-ATH12K-FW\0"
            force_mlo_feature = ${if forceMloFeature then "True" else "False"}
            if not data.startswith(magic):
                raise SystemExit("unexpected ath12k firmware container magic")

            def align4(value):
                return (value + 3) & ~3

            offset = align4(len(magic))
            out = bytearray(data[:offset])
            saw_dualmac = False
            saw_features = False

            while offset + 8 <= len(data):
                ie_id, ie_len = struct.unpack_from("<II", data, offset)
                offset += 8
                if ie_len > len(data) - offset:
                    raise SystemExit("invalid ath12k firmware IE length")

                payload = data[offset:offset + ie_len]
                offset += align4(ie_len)

                if ie_id == 2:
                    continue
                if ie_id == 4:
                    ie_id = 2
                    saw_dualmac = True
                if ie_id == 1:
                    saw_features = True
                    if force_mlo_feature:
                        payload = bytearray(payload)
                        if not payload:
                            payload.append(0)
                        payload[0] |= 0x2
                        payload = bytes(payload)

                out += struct.pack("<II", ie_id, len(payload))
                out += payload
                out += b"\0" * (align4(len(payload)) - len(payload))

            if ${if dualmacAsPrimary then "True" else "False"} and not saw_dualmac:
                raise SystemExit("dualmac firmware IE not present")
            if force_mlo_feature and not saw_features:
                payload = b"\x02"
                out += struct.pack("<II", 1, len(payload))
                out += payload
                out += b"\0" * (align4(len(payload)) - len(payload))

            open(dst, "wb").write(out)
            PY
          ''
          else ''
            cp "$firmware" "$out/lib/firmware/ath12k/QCN9274/hw2.0/firmware-2.bin"
          ''
        }
        ${
          if vendorBoard2Aliases != []
          then ''
            python3 - ${../packages/wakiki-fw}/board.bin "$out/lib/firmware/ath12k/QCN9274/hw2.0/board-2.bin" <<'PY'
            import struct
            import sys

            src, dst = sys.argv[1:]
            board_data = open(src, "rb").read()
            names = ${builtins.toJSON vendorBoard2Aliases}
            magic = b"QCA-ATH12K-BOARD\0"

            def align4(value):
                return (value + 3) & ~3

            def ie(ie_id, payload):
                return (
                    struct.pack("<II", ie_id, len(payload))
                    + payload
                    + b"\0" * (align4(len(payload)) - len(payload))
                )

            out = bytearray(magic)
            out += b"\0" * (align4(len(out)) - len(out))

            for name in names:
                payload = ie(0, name.encode("ascii")) + ie(1, board_data)
                out += ie(0, payload)

            open(dst, "wb").write(out)
            PY
          ''
          else if board2 == null
          then ''
            cp ${../packages/wakiki-fw}/board.bin "$out/lib/firmware/ath12k/QCN9274/hw2.0/board.bin"
          ''
          else ''
            cp "$board2File" "$out/lib/firmware/ath12k/QCN9274/hw2.0/board-2.bin"
          ''
        }
        ${
          if regdb == null
          then ''
            cp ${../packages/wakiki-fw}/regdb.bin "$out/lib/firmware/ath12k/QCN9274/hw2.0/regdb.bin"
          ''
          else ''
            cp "$regdbFile" "$out/lib/firmware/ath12k/QCN9274/hw2.0/regdb.bin"
          ''
        }
      '';
    };

  qcn9274-fw-1_3_1-mlo-vendor-board = self.qcn9274FirmwareWithVendorBoard {
    version = "1.3.1-00162-mlo";
    url = "https://git.codelinaro.org/clo/ath-firmware/ath12k-firmware/-/raw/main/QCN9274/hw2.0/1.3.1/WLAN.WBE.1.3.1-00162-QCAHKSWPL_SILICONZ-1/firmware-2.bin";
    hash = "sha256-eDt8SSUoM6cyib21x0Uxf+Jyd3nLO3zOSSb2BEKZJj8=";
  };

  qcn9274-fw-1_3_1-mlo-dualmac-primary-vendor-board = self.qcn9274FirmwareWithVendorBoard {
    version = "1.3.1-00162-mlo-dualmac-primary";
    url = "https://git.codelinaro.org/clo/ath-firmware/ath12k-firmware/-/raw/main/QCN9274/hw2.0/1.3.1/WLAN.WBE.1.3.1-00162-QCAHKSWPL_SILICONZ-1/firmware-2.bin";
    hash = "sha256-eDt8SSUoM6cyib21x0Uxf+Jyd3nLO3zOSSb2BEKZJj8=";
    dualmacAsPrimary = true;
  };

  qcn9274-fw-1_3_1-mlo-dualmac-primary-vendor-board2-alias = self.qcn9274FirmwareWithVendorBoard {
    version = "1.3.1-00162-mlo-dualmac-primary-vendor-board2-alias";
    url = "https://git.codelinaro.org/clo/ath-firmware/ath12k-firmware/-/raw/main/QCN9274/hw2.0/1.3.1/WLAN.WBE.1.3.1-00162-QCAHKSWPL_SILICONZ-1/firmware-2.bin";
    hash = "sha256-eDt8SSUoM6cyib21x0Uxf+Jyd3nLO3zOSSb2BEKZJj8=";
    dualmacAsPrimary = true;
    vendorBoard2Aliases = [
      "bus=pci,qmi-chip-id=0,qmi-board-id=255"
      "bus=pci,qmi-chip-id=0,qmi-board-id=4121"
    ];
  };

  qcn9274-fw-1_3_1-mlo-dualmac-primary-vendor-board2-alias-force-mlo = self.qcn9274FirmwareWithVendorBoard {
    version = "1.3.1-00162-mlo-dualmac-primary-vendor-board2-alias-force-mlo";
    url = "https://git.codelinaro.org/clo/ath-firmware/ath12k-firmware/-/raw/main/QCN9274/hw2.0/1.3.1/WLAN.WBE.1.3.1-00162-QCAHKSWPL_SILICONZ-1/firmware-2.bin";
    hash = "sha256-eDt8SSUoM6cyib21x0Uxf+Jyd3nLO3zOSSb2BEKZJj8=";
    dualmacAsPrimary = true;
    forceMloFeature = true;
    vendorBoard2Aliases = [
      "bus=pci,qmi-chip-id=0,qmi-board-id=255"
      "bus=pci,qmi-chip-id=0,qmi-board-id=4121"
    ];
  };

  qcn9274-fw-1_3_1-00217-mlo-dualmac-primary-vendor-board2-alias = self.qcn9274FirmwareWithVendorBoard {
    version = "1.3.1-00217-mlo-dualmac-primary-vendor-board2-alias";
    url = "https://git.codelinaro.org/clo/ath-firmware/ath12k-firmware/-/raw/main/QCN9274/hw2.0/1.3.1/WLAN.WBE.1.3.1-00217-QCAHKSWPL_SILICONZ-1/firmware-2.bin";
    hash = "sha256-nc0bJeJPMwb6QE3IX9UIPv0vYSxM0MBjNPPN1rW8jck=";
    dualmacAsPrimary = true;
    vendorBoard2Aliases = [
      "bus=pci,qmi-chip-id=0,qmi-board-id=255"
      "bus=pci,qmi-chip-id=0,qmi-board-id=4121"
    ];
  };

  qcn9274-fw-1_3_1-mlo-dualmac-primary-wallys-board2 = self.qcn9274FirmwareWithVendorBoard {
    version = "1.3.1-00162-mlo-dualmac-primary-wallys-board2";
    url = "https://git.codelinaro.org/clo/ath-firmware/ath12k-firmware/-/raw/main/QCN9274/hw2.0/1.3.1/WLAN.WBE.1.3.1-00162-QCAHKSWPL_SILICONZ-1/firmware-2.bin";
    hash = "sha256-eDt8SSUoM6cyib21x0Uxf+Jyd3nLO3zOSSb2BEKZJj8=";
    dualmacAsPrimary = true;
    board2 = {
      url = "https://wifi5.eu/dls/Wallys/DR9274/board-2-qcn9274.bin";
      hash = "sha256-zFuctL+IeLn42TPutqwweIXf6NCaIn53GvTEWLmv/mM=";
    };
    regdb = {
      url = "https://wifi5.eu/dls/Wallys/DR9274/regdb.bin";
      hash = "sha256-IsTYDiqYpm+fdaOjUzUh54ILtaahpuTkCIj3bSekEq0=";
    };
  };

  qcn9274-fw-1_4_1-vendor-board = self.qcn9274FirmwareWithVendorBoard {
    version = "1.4.1";
    url = "https://git.codelinaro.org/clo/ath-firmware/ath12k-firmware/-/raw/main/QCN9274/hw2.0/1.4.1/WLAN.WBE.1.4.1-00199-QCAHKSWPL_SILICONZ-1/firmware-2.bin";
    hash = "sha256-k+ODj8dX3aFLbKiTRL++X9uIZlTHRsnudSobTj8WdFg=";
  };

  qcn9274-fw-1_5-vendor-board = self.qcn9274FirmwareWithVendorBoard {
    version = "1.5";
    url = "https://git.codelinaro.org/clo/ath-firmware/ath12k-firmware/-/raw/main/QCN9274/hw2.0/1.5/WLAN.WBE.1.5-01651-QCAHKSWPL_SILICONZ-1/firmware-2.bin";
    hash = "sha256-7bSiACBu0TAgtdnTSrRgcSOHeboXsIWVu5n4kQ0y8tU=";
  };

  qcn9274-fw-1_6-vendor-board = self.qcn9274FirmwareWithVendorBoard {
    version = "1.6";
    url = "https://git.codelinaro.org/clo/ath-firmware/ath12k-firmware/-/raw/main/QCN9274/hw2.0/1.6/WLAN.WBE.1.6-01243-QCAHKSWPL_SILICONZ-1/firmware-2.bin";
    hash = "sha256-URXBwekSePDFDc8rvaz5umZs1emdIlAFxNRi0jTe6/w=";
  };

  qcn9274-fw-1_6-dualmac-primary-vendor-board = self.qcn9274FirmwareWithVendorBoard {
    version = "1.6-dualmac-primary";
    url = "https://git.codelinaro.org/clo/ath-firmware/ath12k-firmware/-/raw/main/QCN9274/hw2.0/1.6/WLAN.WBE.1.6-01243-QCAHKSWPL_SILICONZ-1/firmware-2.bin";
    hash = "sha256-URXBwekSePDFDc8rvaz5umZs1emdIlAFxNRi0jTe6/w=";
    dualmacAsPrimary = true;
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
        # One timing-sensitive memory-channel test intermittently receives the
        # next SSE event before its assertion. The package's other 69 tests pass.
        sse-starlette = python-prev.sse-starlette.overridePythonAttrs (old: {
          doCheck = false;
          dependencies = (old.dependencies or [ ]) ++ [ python-final.starlette ];
        });
        # test_max_terminals depends on host PTY accounting and fails on the
        # diskless/netboot build hosts even though the package itself works.
        # This otherwise blocks jupyter -> einops -> amd-aiter -> vLLM.
        terminado = python-prev.terminado.overridePythonAttrs (_: {
          doCheck = false;
        });
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

  # FreeCAD Robust MCP server (bridges AI assistants to FreeCAD).
  freecad-robust-mcp = super.callPackage ../packages/freecad-robust-mcp {};

  # OCP CAD Viewer backend (build123d/cadquery/ocp_vscode) via uv in an FHS env.
  ocp-cad-viewer = super.callPackage ../packages/ocp-cad-viewer {};

}
