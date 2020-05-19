{ fetchFromGitHub, pkgs }:

let
  uboot = pkgs.callPackage <nixpkgs/pkgs/misc/uboot> { stdenv = pkgs.gcc49Stdenv; };
in
uboot.buildUBoot rec {
  pname = "odroid-c1-uboot";
  version = "2011.03";

  src = fetchFromGitHub {
    owner = "hardkernel";
    repo = "u-boot";
    rev = "odroidc-v${version}";
    sha256 = "06lgbfg5ya8bv5nabg77wh1d8x9axr2bpcfhv1ngc4dflrwxjvv3";
  };

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
