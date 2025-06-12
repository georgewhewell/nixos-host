self: super:
{
  # libtorrent-rasterbar = let
  #   newboost = super.libtorrent-rasterbar.override {boost = super.boost187;};
  # in
  #   newboost.overrideAttrs (o: {
  #     version = "uring";
  #     src = super.fetchFromGitHub {
  #       owner = "Chocobo1";
  #       repo = "libtorrent";
  #       rev = "0562a4c60afb08bd7e034ca4f297e2c726264de7";
  #       sha256 = "sha256-i2hjxhDvcrSAmU4+f6yalK70YIUgnDsizAj879b+8t8=";
  #       fetchSubmodules = true;
  #     };
  #     buildInputs = o.buildInputs ++ [super.liburing];
  #     cmakeFlags = o.cmakeFlags ++ ["-Dio_uring=ON"];
  #     nativeBuildInputs = o.nativeBuildInputs ++ [super.pkg-config];
  #   });
  # vpp = super.vpp.overrideAttrs (o: rec {
  #   dontStrip = true;
  #   hardeningDisable = ["all"];
  #   postPatch = ''
  #     patchShebangs scripts/
  #     substituteInPlace CMakeLists.txt \
  #       --replace "tools/perftool cmake pkg" \
  #       "tools/perftool cmake"
  #   '';
  #   version = "25.02";
  #   src = super.fetchFromGitHub {
  #     owner = "FDio";
  #     repo = "vpp";
  #     rev = "v${version}";
  #     hash = "sha256-UDO1mlOEQNCmtR18CCTF+ng5Ms9gfTsnohSygLlPopY=";
  #   };
  # });

  # Override userspace ZFS to use staging source and bypass kernel compatibility
  zfs = (super.zfs.override {
    kernelCompatible = _: true;
  }).overrideAttrs (oldAttrs: {
    src = super.fetchFromGitHub {
      owner = "openzfs";
      repo = "zfs";
      rev = "zfs-2.3.3-staging";
      hash = "sha256-WOHD/hR0Qv9gOT6QJETlb4c9/WhhMCVtMIoGzH5ajII=";
    };
    version = "2.3.3-staging";
  });

  # whatsapp-for-mac = super.whatsapp-for-mac.overrideAttrs (oldAttrs: rec {
  #   version = "2.25.2.80";
  #   src = super.fetchzip {
  #     extension = "zip";
  #     name = "WhatsApp.app";
  #     url = "https://web.whatsapp.com/desktop/mac_native/release/?version=${version}&extension=zip&configuration=Release&branch=relbranch";
  #     hash = "sha256-zTddPh72ggnYoU6AskLpus5Sl3KS8QK1loWH2d0+Eug=";
  #   };
  # });

  # pythonPackagesExtensions =
  #   super.pythonPackagesExtensions
  #   ++ [
  #     (
  #       _: python-prev: {
  #         rapidocr-onnxruntime = python-prev.rapidocr-onnxruntime.overridePythonAttrs (self: {
  #           pythonImportsCheck =
  #             if python-prev.stdenv.isLinux && python-prev.stdenv.isAarch64
  #             then []
  #             else ["rapidocr_onnxruntime"];
  #           doCheck = false;
  #           meta = self.meta // {broken = false;};
  #         });

  #         # chromadb = python-prev.chromadb.overridePythonAttrs (self: {
  #         #   pythonImportsCheck =
  #         #     if python-prev.stdenv.isLinux && python-prev.stdenv.isAarch64
  #         #     then []
  #         #     else ["chromadb"];
  #         #   doCheck = !(python-prev.stdenv.isLinux && python-prev.stdenv.isAarch64);
  #         #   meta = self.meta // {broken = false;};
  #         # });

  #         # langchain-chroma = python-prev.langchain-chroma.overridePythonAttrs (_: {
  #         #   pythonImportsCheck =
  #         #     if python-prev.stdenv.isLinux && python-prev.stdenv.isAarch64
  #         #     then []
  #         #     else ["langchain_chroma"];
  #         #   doCheck = !(python-prev.stdenv.isLinux && python-prev.stdenv.isAarch64);
  #         # });
  #       }
  #     )
  #   ];
  spotify = super.spotify.overrideAttrs (oldAttrs: {
    src = super.fetchurl {
      url = "https://download.scdn.co/SpotifyARM64.dmg";
      sha256 = "sha256-a3LPFX3/f58fuaEJmzcpsgI27yTaRltwftwOuJBN+nQ=";
    };
  });

  wakiki-fw = super.stdenvNoCC.mkDerivation {
    name = "wakiki-firmware";
    src = ../packages/wakiki-fw;

    installPhase = ''
      echo $(ls -la)
      mkdir -p $out/lib/firmware/ath12k/QCN9274/hw2.0
      cp -r * $out/lib/firmware/ath12k/QCN9274/hw2.0/
      cp regdb.bin $out/lib/firmware/regdb.bin
    '';
  };

  ath12k-fw = super.stdenv.mkDerivation {
    name = "ath12k-firmware";

    src = super.fetchFromGitLab {
      domain = "git.codelinaro.org";
      owner = "clo";
      repo = "ath-firmware/ath12k-firmware";
      rev = "5f5f6d6585e0dc3fd32dae8223a8faf5349e6609";
      hash = "sha256-MwLQpfLAQ2SFqHdxr6CVPT8fnA6mozjgqCcqZFPHfX8=";
    };

    # buildPhase = ''
    #   ls -la
    # '';

    # installPhase = ''

    #   cp -r * $out/lib/firmware
    # '';
  };
}
