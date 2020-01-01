{ pkgs }:

let
  uboot = pkgs.pkgsCross.aarch64-multiplatform.callPackage ./uboot.nix { };
in pkgs.writeScript "sd-fuse" ''
  echo "writing to $1"
  dd if=vim2bl/u-boot.bin.sd.bin of=$1 conv=fsync,notrunc bs=512 skip=1 seek=1
  dd if=vim2bl/u-boot.bin.sd.bin of=$1 conv=fsync,notrunc bs=1 count=442
''
