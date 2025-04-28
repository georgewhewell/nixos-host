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

  # zfs = super.zfs.overrideAttrs (oldAttrs: {
  #   meta.broken = false;
  # });

  # linuxPackages_latest =
  #   super.linuxPackages_latest
  #   // {
  #     zfs =
  #       super.linuxPackages_latest.zfs.overrideAttrs
  #       (oldAttrs: {
  #         meta.broken = false;
  #         version = self.zfs.version;
  #         src = super.fetchFromGitHub {
  #           owner = "zfsonlinux";
  #           repo = "zfs";
  #           tag = "88e3885cf4c24d27fcb7e9b13eeaac86629918e7";
  #           hash = "sha256-0v3a3x5g7j8k6q9f8c4h4j4k4j4k4j4k4j4k4j4k4k=";
  #         };
  #       })
  #       .override {
  #         kernelCompatible = _: true;
  #       };
  #   };

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
  wakiki-fw = super.stdenvNoCC.mkDerivation {
    name = "wakiki-firmware";
    src = ../packages/wakiki-fw;
    buildPhase = ''
      echo 1
    '';
    installPhase = ''
      mkdir -p $out/lib/firmware/ath12k/QCN9274/hw2.0
      cp -r * $out/lib/firmware/ath12k/QCN9274/hw2.0/
    '';
  };
}
// (import ../packages {pkgs = super;})
