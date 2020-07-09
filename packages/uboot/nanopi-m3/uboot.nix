{ buildUBoot, sources, pkgs }:

buildUBoot {
  pname = "nanopi-m3-uboot";

  version = sources.u-boot-nanopi-m3.rev;
  src = sources.u-boot-nanopi-m3;

  defconfig = "nanopim3_defconfig";
  targetPlatforms = [ "aarch64-linux" ];
  filesToInstall = [ "u-boot.bin" ];

  nativeBuildInputs = with pkgs.buildPackages; [
    bc
    bison
    flex
    swig
  ];

  buildInputs = [ pkgs.openssl ];

  makeFlags = [
    "DTC=${pkgs.buildPackages.dtc}/bin/dtc"
    "CROSS_COMPILE=${pkgs.stdenv.cc.targetPrefix}"
  ];

  patches = [
    ./uboot-config.patch
  ];

}
