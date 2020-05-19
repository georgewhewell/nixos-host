{ pkgs }:

rec {
  bl1 = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/hardkernel/u-boot/odroidc-v2011.03/sd_fuse/bl1.bin.hardkernel";
    sha256 = "1l4mfykqn09mjsmkvrmn5i8yyq6b84qmarwq77ycgrdpggq9a1b7";
  };
  uboot = pkgs.pkgsCross.armv7l-hf-multiplatform.callPackage ./uboot.nix { };
  write-sd = pkgs.writeScriptBin "write-sd" ''
    dd conv=notrunc if=${bl1} of=$1 bs=1 count=442
    dd conv=notrunc if=${bl1} of=$1 bs=512 skip=1 seek=1
    dd conv=notrunc if=${uboot}/u-boot.bin of=$1 bs=512 seek=64
  '';

}
