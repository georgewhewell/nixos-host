{ buildUBoot, fetchFromGitHub, pkgs }:

buildUBoot {
  pname = "nanopi-m3-uboot";
  version = "1";

  src = fetchFromGitHub {
    owner = "rafaello7";
    repo = "u-boot-nanopi-m3";
    rev = "078a36d65df40ab876a3030d1db8274426576e4f";
    sha256 = "0mlq1ndvyncy48rhlpik972lp1za7715v0kkik99l6x3i8l7gxay";
  };

  defconfig = "nanopim3_defconfig";
  targetPlatforms = [ "aarch64-linux" ];
  filesToInstall = [ "u-boot.bin" ];

  nativeBuildInputs = with pkgs; [
    bc
    bison
    flex
    openssl
    swig
  ];

  makeFlags = [
    "DTC=${pkgs.buildPackages.dtc}/bin/dtc"
    "CROSS_COMPILE=${pkgs.stdenv.cc.targetPrefix}"
  ];

  patches = [
    ./uboot-config.patch
  ];

}
