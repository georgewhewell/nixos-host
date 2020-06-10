{ fetchFromGitHub, pkgs }:

let
  /* uboot = pkgs.callPackage <nixpkgs/pkgs/misc/uboot> { stdenv = pkgs.gcc49Stdenv; }; */
in
pkgs.buildUBoot rec {
  pname = "amlogic-s912-uboot";
  version = "master";

  defconfig = "odroidc_config";
  targetPlatforms = [ "armv7l-linux" ];
  filesToInstall = [ "sd_fuse/u-boot.bin" "sd_fuse/bl1.bin.hardkernel" ];

  enableParallelBuilding = false;
  postPatch = ''
    patchShebangs .
  '';

  patches = [ ./fixup.patch ];
  buildInputs = [ pkgs.gcc49Stdenv ];
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

}
